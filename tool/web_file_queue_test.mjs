import assert from 'node:assert/strict';
import { FileQueue } from '../docs/web/file-queue.mjs';

const controls = new Map();
globalThis.document = { getElementById(id) { if (!controls.has(id)) controls.set(id, {}); return controls.get(id); } };
const offers = [], cancelled = [], errors = [];
const session = {
  state: 'connected', primary: { id: 'charlie' },
  peers: new Map(['charlie', 'bravo'].map(id => [id, { peer: { state: 'connected' } }])),
  offerFile(file, recipient) { const id = `file-${offers.length}`; offers.push({ file, recipient, id }); return id; },
  cancelFile(id) { cancelled.push(id); },
};
const queue = new FileQueue({ getSession: () => session, onError: error => errors.push(error.code) });
queue.add([new File(['one'], 'first.txt'), new File(['two'], 'second.txt')]);
assert.equal(offers[0].recipient, 'charlie');
session.primary = { id: 'bravo' };
queue.transfer({ id: offers[0].id, state: 'complete' });
await Promise.resolve();
assert.equal(offers[1].recipient, 'charlie', 'a queued file keeps the selected recipient at enqueue time');
assert.equal(session.primary.id, 'bravo', 'advancing the queue never changes the current recipient or fingerprint selection');
queue.transfer({ id: offers[1].id, state: 'complete' }); await Promise.resolve();
queue.add([new File([], 'next.txt')]);
assert.equal(offers[2].recipient, 'bravo', 'new attachments use the current visible recipient');
queue.add([new File(['pending'], 'pending.txt')]);
controls.get('cancel-file-queue').onclick();
assert.equal(queue.pending.length, 0); assert.deepEqual(cancelled, [offers[2].id]);
session.peers.delete('bravo'); queue.add([new File(['lost'], 'lost.txt')]);
assert.deepEqual(errors, ['not-connected']); assert.equal(queue.pending.length, 0);
assert.throws(() => queue.add([new File(['x'], '../unsafe.txt')]));
assert.throws(() => queue.add(Array.from({ length: 101 }, () => new File([], 'many.txt'))));
console.log('web file queue: consent sequencing, pinned queued recipient, unchanged selection, cancellation, disconnect and bounds passed');
