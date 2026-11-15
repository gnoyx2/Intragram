import { bytes, b64, encode, hash, random, verify, sign, peerId, equal, fail, integer, attestationBytes, verifyAttestation } from './evidence-wire.mjs';
const concat = (...parts) => new Uint8Array(parts.flatMap(p => Array.from(p)));
const leaf = async (salt, a) => hash(concat([0], salt, attestationBytes(a), bytes(a.sg, 64)));
const node = async (a, b) => hash(concat([1], a, b));
const batchBytes = b => encode(['intragram/merkle-batch/v1', b.no, b.n, b.rt, b.sa, b.pk]);
const anchorBytes = a => encode(['intragram/anchor-receipt/v1', a.no, a.n, a.rt, a.rk, a.wk, a.wa, a.nc]);
function header(b) {
  if (!b || !integer(b.no, 1) || !integer(b.n, 1, 1 << 20) || !integer(b.sa)) fail();
  bytes(b.rt, 32); bytes(b.pk, 32); bytes(b.sg, 64); return b;
}
async function levels(leaves) {
  const result = [leaves];
  while (result.at(-1).length > 1) {
    const current = result.at(-1), next = [];
    for (let i = 0; i < current.length; i += 2) next.push(i + 1 < current.length ? await node(current[i], current[i + 1]) : current[i]);
    result.push(next);
  }
  return result;
}
export async function exportEvidenceBundle(owner) {
  if (owner.lastBundle && owner.lastBundleRevision === owner.revision) return JSON.stringify(owner.lastBundle, null, 2);
  const entries = owner.entries.filter(e => ['issued', 'verified'].includes(e.status));
  if (!entries.length) fail();
  const generation = owner.generation;
  const tree = await levels(await Promise.all(entries.map(e => leaf(bytes(e.salt, 16), e.attestation))));
  const batch = { no: owner.nextBatch++, n: entries.length, rt: b64(tree.at(-1)[0]), sa: Date.now(), pk: owner.publicKey };
  batch.sg = b64(await sign(owner.keys.privateKey, batchBytes(batch)));
  if (generation !== owner.generation) fail();
  const raw = { format: 'intragram-audit-anchor-bundle/v1', batch, entries: entries.map((entry, index) => {
    const proof = []; let i = index;
    for (const level of tree) { if (level.length <= 1) break; const sibling = i % 2 ? i - 1 : i + 1;
      if (sibling < level.length) proof.push(b64(level[sibling])); i = Math.floor(i / 2); }
    return { index, salt: entry.salt, attestation: entry.attestation, proof };
  }) };
  owner.lastBundle = raw;
  owner.lastBundleRevision = owner.revision;
  return JSON.stringify(raw, null, 2);
}
export async function verifyEvidenceBundle(text, expectedWitnessPeerId) {
  try {
    if (typeof text !== 'string' || text.length > 4 * 1024 * 1024) return false;
    const raw = JSON.parse(text), b = header(raw.batch);
    if (raw.format !== 'intragram-audit-anchor-bundle/v1' || !Array.isArray(raw.entries) ||
        !raw.entries.length || raw.entries.length > 512 || raw.entries.length > b.n || !await verify(bytes(b.pk, 32), bytes(b.sg, 64), batchBytes(b))) return false;
    const seen = new Set(), events = new Set();
    for (const entry of raw.entries) {
      if (!integer(entry.index, 0, b.n - 1) || seen.has(entry.index) || events.has(entry.attestation?.e) ||
          !Array.isArray(entry.proof) || entry.proof.length > 64) return false;
      seen.add(entry.index); events.add(entry.attestation.e);
      let current = await leaf(bytes(entry.salt, 16), entry.attestation), index = entry.index, width = b.n, used = 0;
      while (width > 1) {
        const sibling = index % 2 ? index - 1 : index + 1;
        if (sibling < width) {
          if (used >= entry.proof.length) return false;
          const other = bytes(entry.proof[used++], 32);
          current = index % 2 ? await node(other, current) : await node(current, other);
        }
        index = Math.floor(index / 2); width = Math.ceil(width / 2);
      }
      if (used !== entry.proof.length || !equal(current, bytes(b.rt, 32)) || !await verifyAttestation(entry.attestation)) return false;
    }
    if (raw.anchor != null) {
      if (!await verifyAnchor(raw.anchor, b, expectedWitnessPeerId)) return false;
    } else if (expectedWitnessPeerId) return false;
    return true;
  } catch { return false; }
}
export async function verifyAnchor(a, b, expected) {
  try {
    if (!a || !integer(a.wa) || a.no !== b.no || a.n !== b.n || a.rt !== b.rt || a.rk !== b.pk || a.rk === a.wk) return false;
    bytes(a.nc, 16);
    if (expected && await peerId(bytes(a.wk, 32)) !== expected) return false;
    return await verify(bytes(a.wk, 32), bytes(a.sg, 64), anchorBytes(a));
  } catch { return false; }
}
export async function witnessEvidenceBundle(owner, text) {
  if (!await verifyEvidenceBundle(text)) fail();
  const b = JSON.parse(text).batch;
  if (b.pk === owner.publicKey) fail();
  const anchor = { no: b.no, n: b.n, rt: b.rt, rk: b.pk, wk: owner.publicKey, wa: Date.now(), nc: b64(random(16)) };
  anchor.sg = b64(await sign(owner.keys.privateKey, anchorBytes(anchor)));
  return JSON.stringify(anchor, null, 2);
}
