import assert from 'node:assert/strict';
import { ChatExperience } from '../docs/web/chat.mjs';
import { PeerSession } from '../docs/web/peer.mjs';
import { newId } from '../docs/web/protocol.mjs';

const controls = new Map();
const element = () => ({
  value: '', hidden: false, scrollHeight: 0, scrollTop: 0, clientHeight: 100,
  dataset: {}, addEventListener() {}, append() {}, remove() {}, focus() {},
  querySelector() { return null; },
});
globalThis.document = {
  hidden: true, addEventListener() {}, createElement: element,
  getElementById(id) {
    if (!controls.has(id)) controls.set(id, element());
    return controls.get(id);
  },
};
globalThis.window = {};
let chat;
const peer = new PeerSession({
  onMessage: frame => chat.add(frame, false),
  onControl: control => chat.control(control),
});
peer.state = 'connected';
peer.channel = { readyState: 'open', bufferedAmount: 0, send() {}, close() {} };
chat = new ChatExperience({ getSession: () => peer, onError: error => { throw error; } });
// Rendering is orthogonal: exercise the actual receive, add, burn, eviction, and clear paths.
chat.render = () => {};
chat.search = () => {};
const receive = (kind, value) => peer._receive(JSON.stringify({ kind, id: newId(), ...value }));
const id = 'a'.repeat(32);
receive('text', { id, text: 'burn this' });
assert.equal(chat.messages.get(id)?.text, 'burn this');
receive('control', { control: { k: 'burn', id } });
assert.equal(chat.messages.has(id), false);
for (let i = 0; i < 1005; i++) receive('text', { text: String(i) });
assert.equal(peer.seenMessages.has(id), false, 'transport window really advanced');
assert.equal(chat.messages.size, 500, 'the visible transcript remains bounded');
receive('text', { id, text: 'replayed after burn' });
assert.equal(chat.messages.has(id), false, 'burned text cannot reappear after replay-window eviction');
const local = [...chat.messages.keys()][0];
chat.remove(local);
receive('text', { id: local, text: 'replayed after local deletion' });
assert.equal(chat.messages.has(local), false);
chat.clear();
assert.equal(chat.seenMessageIds.size, 0, 'clearing a session releases the tombstones');
peer.close();
console.log('auxiliary chat replay: burned/local-deleted IDs remain retired beyond the transport window; session clear releases metadata');
