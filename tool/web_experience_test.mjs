import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
import { validateControl } from '../docs/web/protocol.mjs';
import { sealVault, openVault } from '../docs/web/vault.mjs';
import { pcmWav } from '../docs/web/media.mjs';
import { receiveBudget } from '../docs/web/receive-budget.mjs';
import { WebPeerIdentity, WebPeerEvidence } from '../docs/web/evidence.mjs';

globalThis.crypto ||= webcrypto;
const id = 'a'.repeat(32), other = 'b'.repeat(32);
for (const control of [
  { k: 'typing', on: true }, { k: 'read', id }, { k: 'burn', id }, { k: 'receipt', id },
  { k: 'react', id, emoji: '❤️', on: true }, { k: 'meta', id, ttl: 5, replyTo: other, quote: '<script>' },
  { k: 'rename', alias: '이름' }, { k: 'verify', sas: '123456' },
  { k: 'room-state', self: id, host: other, members: [{ id, alias: 'Guest' }, { id: other, alias: 'Host' }] },
  { k: 'room-msg', id, origin: other, alias: 'Host', text: '그룹 메시지' },
  { k: 'room-control', origin: id, control: { k: 'react', id: other, emoji: '👍', on: true } },
  { k: 'native-room', frame: { k: 'capabilities', v: 1 } },
]) assert.equal(validateControl(control), control);
for (const control of [
  { k: 'typing', on: 'true' }, { k: 'read', id: 'bad' }, { k: 'meta', id, ttl: 1 },
  { k: 'react', id, emoji: '<script>', on: true }, { k: 'rename', alias: 'x\n' },
  { k: 'room-state', self: id, host: id, members: [{ id, alias: 'a' }, { id, alias: 'b' }] },
  { k: 'room-msg', id, origin: other, alias: 'Host', text: 'x'.repeat(16385) },
  { k: 'room-control', origin: id, control: { k: 'room-control', origin: id, control: { k: 'read', id } } },
  { k: 'room-control', origin: id, control: { k: 'verify', sas: '123456' } },
  { k: 'native-room', frame: { k: 'capabilities', v: 2 } },
  { k: 'native-room', frame: { k: 'unknown' } },
  { k: 'native-room', frame: { k: 'msg', body: 'x'.repeat(16385) } },
]) assert.throws(() => validateControl(control));
const snapshot = { version: 1, messages: [{ id, text: '비밀 <script> 텍스트', mine: true, ts: Date.now() }] };
const sealed = await sealVault(snapshot, 'correct horse battery staple');
assert.ok(!JSON.stringify(sealed).includes('비밀'));
assert.deepEqual(await openVault(sealed, 'correct horse battery staple'), snapshot);
await assert.rejects(openVault(sealed, 'wrong password'));
const tampered = structuredClone(sealed); tampered.cipher = (tampered.cipher[0] === 'A' ? 'B' : 'A') + tampered.cipher.slice(1);
await assert.rejects(openVault(tampered, 'correct horse battery staple'));
await assert.rejects(sealVault(snapshot, 'short'));
assert.notEqual((await sealVault(snapshot, 'correct horse battery staple')).cipher, sealed.cipher);
const wav = pcmWav(new Float32Array([-1, 0, 1, 2])); const wavView = new DataView(wav);
assert.equal(new TextDecoder().decode(wav.slice(0, 4)), 'RIFF'); assert.equal(wav.byteLength, 52);
assert.equal(wavView.getUint32(24, true), 16000); assert.equal(wavView.getUint32(40, true), 8);
assert.equal(wavView.getInt16(44, true), -32768); assert.equal(wavView.getInt16(48, true), 32767); assert.equal(wavView.getInt16(50, true), 32767);
assert.deepEqual(receiveBudget([
  { direction: 'receive', state: 'transferring', size: 70 * 1024 * 1024 },
  { direction: 'receive', state: 'complete', size: 10 * 1024 * 1024, blob: {} },
  { direction: 'receive', state: 'offered', size: 40 * 1024 * 1024 },
  { direction: 'receive', state: 'failed', size: 90 * 1024 * 1024 },
  { direction: 'send', state: 'transferring', size: 90 * 1024 * 1024 },
]), { bytes: 80 * 1024 * 1024, files: 2 });
const sharedIdentity = new WebPeerIdentity(), firstFrames = [], secondFrames = [];
const first = new WebPeerEvidence({ identity: sharedIdentity, sendControl: value => firstFrames.push(value) });
const second = new WebPeerEvidence({ identity: sharedIdentity, sendControl: value => secondFrames.push(value) });
const bindingOne = Buffer.alloc(32, 1).toString('base64'), bindingTwo = Buffer.alloc(32, 2).toString('base64');
await first.start(bindingOne); await second.start(bindingTwo);
assert.equal(first.publicKey, second.publicKey, 'all live links share the application identity');
assert.notEqual(firstFrames[0].sg, secondFrames[0].sg, 'identity proofs still bind each DTLS session');
const receiver = new WebPeerEvidence({ sendControl() {} }); await receiver.start(bindingTwo, { dialled: false });
await receiver.receive(firstFrames[0]); assert.equal(receiver.peerIdentity, null, 'old link identity proof cannot replay');
await receiver.receive(secondFrames[0]); assert.equal(receiver.peerIdentity.peerId, sharedIdentity.peerId);
const oldPublicKey = sharedIdentity.publicKey;
first.clear(); second.clear(); sharedIdentity.clear(); await sharedIdentity.ready();
assert.notEqual(sharedIdentity.publicKey, oldPublicKey, 'panic rotation replaces the ephemeral identity');
console.log('web experience: control bounds, group nesting/identity bounds, encrypted vault round trip, wrong-password/tamper rejection and fresh nonces passed');
