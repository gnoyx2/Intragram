import assert from 'node:assert/strict';
import { PeerSession } from '../docs/web/peer.mjs';
import { MAX_FILE_BYTES, MAX_TEXT_BYTES, MAX_CODE_CHARS, CHUNK_BYTES, newId,
  localAddress, encodeDescription, decodeCode, validateDescription, parseFrame,
  makeChunk, parseChunk } from '../docs/web/protocol.mjs';

const id = '0123456789abcdef0123456789abcdef';
const fingerprint = Array(32).fill('AB').join(':');
const sdp = [
  'v=0', 'o=- 1 1 IN IP4 127.0.0.1', 's=-', 't=0 0',
  'a=group:BUNDLE 0', 'm=application 9 UDP/DTLS/SCTP webrtc-datachannel',
  'c=IN IP4 0.0.0.0', 'a=mid:0', 'a=ice-ufrag:abcd',
  'a=ice-pwd:abcdefghijklmnopqrstuvwxyz', `a=fingerprint:sha-256 ${fingerprint}`,
  'a=setup:actpass', 'a=sctp-port:5000',
  'a=candidate:1 1 udp 2122260223 192.168.0.5 50000 typ host generation 0', '',
].join('\r\n');

function expectCode(fn, code) {
  assert.throws(fn, error => error.code === code);
}

function testDescriptions() {
  const offer = { type: 'offer', sdp };
  const code = encodeDescription(offer);
  assert.ok(code.startsWith('IGW1.'));
  assert.ok(!code.includes('='));
  assert.deepEqual(decodeCode(code, 'offer'), offer);
  assert.deepEqual(decodeCode(` \n${code}\n `), offer);
  expectCode(() => decodeCode(code, 'answer'), 'invalid-code');
  for (const bad of [null, '', 'IGA1.abc', 'IGW1.!', 'IGW1.' + 'a'.repeat(MAX_CODE_CHARS),
    'IGW1.' + btoa('{"v":2}'), 'IGW1.' + btoa('null')]) {
    expectCode(() => decodeCode(bad), 'invalid-code');
  }
  for (const altered of [
    sdp.replace('192.168.0.5', '8.8.8.8'),
    sdp.replace('typ host', 'typ srflx'),
    sdp.replace('typ host', 'typ relay'),
    sdp.replace('typ host', 'typ host raddr 8.8.8.8 rport 20'),
    sdp.replace('50000', '0'), sdp.replace('50000', '65536'),
    sdp.replace('m=application', 'm=audio'),
    sdp + 'm=audio 9 UDP/TLS/RTP/SAVPF 0\r\n',
    sdp.replace('sha-256', 'sha-1'),
    sdp + `a=fingerprint:sha-256 ${fingerprint}\r\n`,
    sdp + `a=fingerprint:sha-1 ${fingerprint}\r\n`,
    sdp + 'a=remote-candidates:1 8.8.8.8 444\r\n',
    sdp.replace('a=ice-pwd:abcdefghijklmnopqrstuvwxyz', 'a=ice-pwd:short'),
    sdp.replace('v=0', 'v=0\u0000'),
  ]) expectCode(() => validateDescription({ type: 'offer', sdp: altered }, 'offer'), 'invalid-code');
  const mixed = { type: 'offer', sdp: sdp + 'a=candidate:2 1 udp 1 8.8.8.8 5555 typ host\r\n' };
  assert.ok(!decodeCode(encodeDescription(mixed)).sdp.includes('8.8.8.8'));
  expectCode(() => encodeDescription({ type: 'offer', sdp: sdp.replace('192.168.0.5', '8.8.8.8') }), 'invalid-code');
  for (const host of ['10.0.0.1', '172.16.0.1', '172.31.255.255', '192.168.255.255', '169.254.1.2',
    '127.0.0.1', 'fd12::1', 'fc12:abcd::1', 'fe80::1', '::1', '2c5bf3c4.local']) assert.ok(localAddress(host), host);
  for (const host of ['8.8.8.8', '100.64.0.1', '172.15.0.1', '172.32.0.1', '192.168.00.1',
    '192.168.1.256', '10.1', '2130706433', '2001:4860:4860::8888', 'localhost', 'evil.com', 'a.local.evil.com',
    'fd12::1%eth0']) assert.ok(!localAddress(host), host);
}

function testFrames() {
  const text = { kind: 'text', id, text: '안녕, Intragram!' };
  assert.deepEqual(parseFrame(JSON.stringify(text)), text);
  assert.equal(parseFrame(JSON.stringify({ ...text, text: 'x'.repeat(MAX_TEXT_BYTES) })).text.length, MAX_TEXT_BYTES);
  for (const frame of [null, [], {}, { ...text, id: '' }, { ...text, text: ' ' },
    { ...text, text: '한'.repeat(MAX_TEXT_BYTES) }, { ...text, kind: 'script' },
    { kind: 'file-offer', id, name: '../file', size: 2 },
    { kind: 'file-offer', id, name: 'a\\b', size: 2 },
    { kind: 'file-offer', id, name: 'a\n.txt', size: 2 },
    { kind: 'file-offer', id, name: 'a.txt', size: -1 },
    { kind: 'file-offer', id, name: 'a.txt', size: MAX_FILE_BYTES + 1 },
    { kind: 'file-offer', id, name: 'a.txt', size: 1.5 },
    { kind: 'file-offer', id, name: 'a.txt', size: '2' },
  ]) expectCode(() => parseFrame(JSON.stringify(frame)), 'invalid-frame');
  expectCode(() => parseFrame('{invalid'), 'invalid-frame');
  const bytes = new Uint8Array([0, 1, 255, 20]);
  const chunk = parseChunk(makeChunk(id, 1234, bytes.buffer));
  assert.equal(chunk.id, id);
  assert.equal(chunk.offset, 1234);
  assert.deepEqual(new Uint8Array(chunk.bytes), bytes);
  for (const bad of [null, '', new Uint8Array(21), new ArrayBuffer(20), new ArrayBuffer(CHUNK_BYTES + 21)]) {
    expectCode(() => parseChunk(bad), 'invalid-frame');
  }
  assert.match(newId(), /^[a-f0-9]{32}$/);
  assert.notEqual(newId(), newId());
}

class Channel extends EventTarget {
  constructor() { super(); this.readyState = 'open'; this.bufferedAmount = 0; this.sent = []; }
  send(data) {
    if (this.readyState !== 'open') throw Error('closed');
    this.sent.push(data);
    queueMicrotask(() => { if (this.peer?.readyState === 'open') this.peer.onmessage?.({ data }); });
  }
  close() { this.readyState = 'closed'; }
}

function pair() {
  const aEvents = [], bEvents = [], aMessages = [], bMessages = [], errors = [];
  const a = new PeerSession({ onTransfer: t => aEvents.push(t), onMessage: m => aMessages.push(m), onError: e => errors.push(e) });
  const b = new PeerSession({ onTransfer: t => bEvents.push(t), onMessage: m => bMessages.push(m), onError: e => errors.push(e) });
  const aChannel = new Channel(), bChannel = new Channel();
  aChannel.peer = bChannel; bChannel.peer = aChannel;
  a._attach(aChannel); b._attach(bChannel);
  a.state = b.state = 'connected';
  return { a, b, aChannel, bChannel, aEvents, bEvents, aMessages, bMessages, errors, close() { a.close(); b.close(); } };
}
async function until(condition) {
  for (let i = 0; i < 100; i++) {
    if (condition()) return;
    await new Promise(resolve => setTimeout(resolve, 2));
  }
  assert.ok(condition(), 'operation did not complete');
}

async function testTextAndFiles() {
  const p = pair();
  try {
    const messageId = p.a.sendText('메시지 😀');
    await until(() => p.bMessages.length === 1);
    assert.deepEqual(p.bMessages, [{ id: messageId, text: '메시지 😀' }]);
    p.aChannel.send(JSON.stringify({ kind: 'text', id: messageId, text: 'replay' }));
    await new Promise(resolve => setTimeout(resolve, 0));
    assert.equal(p.bMessages.length, 1);
    expectCode(() => p.a.sendText('x'.repeat(MAX_TEXT_BYTES + 1)), 'text-too-large');
    const bytes = crypto.getRandomValues(new Uint8Array(CHUNK_BYTES * 2 + 5));
    const file = new File([bytes], '문서.bin');
    const fileId = p.a.offerFile(file);
    await until(() => p.bEvents.some(t => t.id === fileId));
    assert.equal(p.bEvents.at(-1).state, 'offered');
    assert.equal(p.aChannel.sent.filter(frame => frame instanceof ArrayBuffer).length, 0, 'no file bytes before acceptance');
    expectCode(() => p.a.offerFile(file), 'transfer-busy');
    p.b.acceptFile(fileId);
    await until(() => p.aEvents.at(-1).state === 'complete');
    const received = p.bEvents.at(-1);
    assert.equal(received.state, 'complete');
    assert.equal(received.transferred, bytes.length);
    assert.deepEqual(new Uint8Array(await received.blob.arrayBuffer()), bytes);
    assert.equal(p.aChannel.sent.filter(frame => frame instanceof ArrayBuffer).length, 3);
    assert.equal(p.a.outgoing.file, null);
    assert.equal(p.b.incoming.chunks, null);
    const emptyId = p.b.offerFile(new File([], 'empty.txt'));
    await until(() => p.a.incoming?.id === emptyId);
    p.a.acceptFile(emptyId);
    await until(() => p.bEvents.at(-1).state === 'complete');
    assert.equal(p.aEvents.at(-1).blob.size, 0);
    assert.equal(p.errors.length, 0);
  } finally { p.close(); }
}

async function testRefusalCancellationAndCleanup() {
  const p = pair();
  try {
    let fileId = p.a.offerFile(new File(['abc'], 'decline.txt'));
    await until(() => p.b.incoming?.id === fileId);
    p.b.rejectFile(fileId);
    await until(() => p.a.outgoing.state === 'rejected');
    fileId = p.a.offerFile(new File(['abc'], 'cancel.txt'));
    await until(() => p.b.incoming?.id === fileId);
    p.a.cancelFile(fileId);
    await until(() => p.b.incoming.state === 'cancelled');
    assert.equal(p.a.outgoing.file, null);
    assert.equal(p.b.incoming.chunks, null);
    fileId = p.a.offerFile(new File(['abc'], 'disconnect.txt'));
    await until(() => p.b.incoming?.id === fileId);
    p.a.close(); p.b.close();
    assert.equal(p.a.outgoing.state, 'failed');
    assert.equal(p.b.incoming.state, 'failed');
    expectCode(() => p.a.sendText('no'), 'not-connected');
  } finally { p.close(); }
}

async function testMalformedTransfers() {
  for (const attack of ['offset', 'overflow', 'early-end', 'early-receipt', 'malformed']) {
    const p = pair();
    try {
      const fileId = p.a.offerFile(new File(['123'], 'bytes.txt'));
      await until(() => p.b.incoming?.id === fileId);
      p.b.incoming.state = 'transferring';
      p.b.incoming.chunks = [];
      if (attack === 'offset') p.aChannel.send(makeChunk(fileId, 1, new Uint8Array([1]).buffer));
      if (attack === 'overflow') p.aChannel.send(makeChunk(fileId, 0, new Uint8Array(4).buffer));
      if (attack === 'early-end') p.aChannel.send(JSON.stringify({ kind: 'file-end', id: fileId }));
      if (attack === 'early-receipt') {
        p.a.outgoing.state = 'transferring';
        p.bChannel.send(JSON.stringify({ kind: 'file-done', id: fileId }));
      }
      if (attack === 'malformed') p.aChannel.send('{broken json');
      await until(() => p.errors.length > 0);
      assert.equal(attack === 'early-receipt' ? p.a.state : p.b.state, 'closed');
      if (attack !== 'early-receipt') assert.equal(p.b.incoming.chunks, null);
      assert.ok(!p.aEvents.some(t => t.state === 'complete') && !p.bEvents.some(t => t.state === 'complete'));
    } finally { p.close(); }
  }
}

async function testBackpressure() {
  const p = pair();
  try {
    p.aChannel.bufferedAmount = 512 * 1024;
    let resolved = false;
    const wait = p.a._backpressure().then(() => { resolved = true; });
    await new Promise(resolve => setTimeout(resolve, 2));
    assert.equal(resolved, false);
    p.aChannel.bufferedAmount = 0;
    p.aChannel.dispatchEvent(new Event('bufferedamountlow'));
    await wait;
    assert.equal(resolved, true);
    p.aChannel.bufferedAmount = 512 * 1024;
    const cancelled = p.a._backpressure();
    p.a.close();
    await assert.rejects(cancelled, error => error.code === 'session-closed');
    assert.equal(p.a.waiters.size, 0);
  } finally { p.close(); }
}

async function testSessionLifecycle() {
  const original = globalThis.RTCPeerConnection;
  const configurations = [];
  class Peer extends EventTarget {
    constructor(configuration) {
      super();
      configurations.push(configuration);
      this.iceGatheringState = 'complete';
      this.connectionState = 'new';
    }
    createDataChannel() { return new Channel(); }
    async createOffer() { return { type: 'offer', sdp }; }
    async createAnswer() { return { type: 'answer', sdp: sdp.replace('actpass', 'active') }; }
    async setLocalDescription(description) { this.localDescription = description; }
    async setRemoteDescription(description) { this.remoteDescription = description; }
    close() { this.connectionState = 'closed'; }
  }
  globalThis.RTCPeerConnection = Peer;
  const a = new PeerSession(), b = new PeerSession();
  try {
    await assert.rejects(b.acceptOffer('broken'), error => error.code === 'invalid-code');
    assert.equal(configurations.length, 0, 'invalid invites create no network session');
    const offer = await a.createOffer();
    assert.equal(a.state, 'waiting');
    const answer = await b.acceptOffer(offer);
    assert.equal(b.state, 'connecting');
    await a.acceptAnswer(answer);
    assert.equal(a.state, 'connecting');
    assert.ok(configurations.every(c => c.iceServers.length === 0 && c.iceCandidatePoolSize === 0));
    await a._fingerprint(); await b._fingerprint();
    assert.match(a.verificationCode, /^\d{6}$/);
    assert.equal(a.verificationCode, b.verificationCode);
    await assert.rejects(a.createOffer(), error => error.code === 'session-in-use');
  } finally { a.close(); b.close(); }
  const pending = new PeerSession();
  try {
    const creating = pending.createOffer();
    pending.pc.iceGatheringState = 'gathering';
    await until(() => pending.waiters.size === 1);
    pending.close();
    await assert.rejects(creating, error => error.code === 'session-closed');
    assert.equal(pending.waiters.size, 0);
    assert.equal(pending.pc, null);
  } finally { pending.close(); globalThis.RTCPeerConnection = original; }
}

for (const test of [testDescriptions, testFrames, testTextAndFiles, testRefusalCancellationAndCleanup,
  testMalformedTransfers, testBackpressure, testSessionLifecycle]) {
  await test();
  console.log(`${test.name}: PASS`);
}
console.log('web peer: PASS (codes, LAN-only candidates, bounded frames, consent, chunks, receipts, cancellation, cleanup, backpressure)');
