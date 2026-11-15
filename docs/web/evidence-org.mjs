import { bytes, b64, encode, hash, verify, sign, peerId, id, label, fail, credential, credentialBytes, credentialDigest } from './evidence-wire.mjs';

export function parseTrustBundle(raw) {
  if (typeof raw === 'string') { if (raw.length > 256 * 1024) fail(); raw = JSON.parse(raw); }
  if (!raw || !id(raw.id) || typeof raw.snapshot !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(raw.snapshot) ||
      !Array.isArray(raw.issuers) || raw.issuers.length > 64 || raw.revoked != null && !Array.isArray(raw.revoked)) fail();
  const ids = new Set();
  for (const issuer of raw.issuers) {
    if (!issuer || !id(issuer.id) || typeof issuer.name !== 'string' || !issuer.name.trim() || issuer.name.length > 96 ||
        ids.has(issuer.id) || !Array.isArray(issuer.policies) || !issuer.policies.length || issuer.policies.length > 64 || issuer.policies.some(p => !label(p))) fail();
    bytes(issuer.key, 32); ids.add(issuer.id);
  }
  if ((raw.revoked || []).length > 4096 || (raw.revoked || []).some(v => !id(v))) fail();
  return raw;
}
export function orgPopBytes(c, binding, dialled, holder, verifier) {
  return encode(['intragram/org-pop/v1', c.digest, c.policy, binding, dialled ? 'D' : 'L', holder, verifier]);
}
export async function presentOrganization(owner) {
  const c = owner.credential;
  if (!c || !owner.peerIdentity || !owner.binding || Date.now() >= c.exp) return;
  const generation = owner.generation;
  const digest = await credentialDigest(c);
  const pop = await sign(owner.keys.privateKey, orgPopBytes({ digest, policy: c.pol }, owner.binding,
    owner.dialled, owner.peerId, owner.peerIdentity.peerId));
  if (generation !== owner.generation) return;
  await owner.sendControl({ k: 'org-credential', credential: c, credentialDigest: digest, policy: c.pol, pop: b64(pop) });
}
export async function checkOrganization(owner, raw) {
  if (raw.credential == null) { owner.organization = null; owner.presentation = null; return; }
  if (!owner.peerIdentity) return;
  const generation = owner.generation, c = credential(raw.credential), trust = owner.trust;
  if (raw.credentialDigest !== await credentialDigest(c) || raw.policy !== c.pol) return;
  owner.presentation = raw;
  const issuer = trust?.issuers.find(i => i.id === c.iss && i.key === c.ik);
  let check = 'verified';
  if (!issuer) check = 'untrustedIssuer';
  else if (!await verify(bytes(c.ik, 32), bytes(c.sg, 64), credentialBytes(c))) check = 'invalidSignature';
  else if (!issuer.policies.includes(c.pol)) check = 'policyMismatch';
  else if ((trust.revoked || []).includes(c.id)) check = 'revoked';
  else if (trust.snapshot !== c.snap) check = 'snapshotMismatch';
  else if (Date.now() >= c.exp) check = 'expired';
  else if (Date.now() + 300000 < c.iat) check = 'notYetValid';
  else if (await peerId(bytes(c.sk, 32)) !== owner.peerIdentity.peerId) check = 'subjectMismatch';
  else if (!await verify(bytes(c.sk, 32), bytes(raw.pop, 64), orgPopBytes({ digest: raw.credentialDigest, policy: c.pol },
    owner.binding, !owner.dialled, owner.peerIdentity.peerId, owner.peerId))) check = 'invalidPop';
  if (generation === owner.generation && trust === owner.trust && owner.presentation === raw) owner.organization = { check, credential: c, verified: check === 'verified', issuerName: issuer?.name, demo: issuer?.demo === true };
}
