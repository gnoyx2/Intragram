import assert from 'node:assert/strict';
import { WebPeerEvidence } from '../docs/web/evidence.mjs';

const sent = [];
const evidence = new WebPeerEvidence({ sendControl: async frame => sent.push(frame) });
try {
  await evidence.start(Buffer.alloc(32, 7).toString('base64'));
  const reflected = sent[0];
  await evidence.receive(reflected);
  assert.equal(evidence.peerIdentity, null,
    'our signature cannot authenticate the opposite peer by reflection');
  console.log('PASS: reflected browser identity rejected');
} finally {
  evidence.clear();
}
