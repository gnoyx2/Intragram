const encoder = new TextEncoder();
export const encode = value => encoder.encode(JSON.stringify(value));
export const b64 = value => btoa(Array.from(new Uint8Array(value), b => String.fromCharCode(b)).join(''));
export const fail = () => { throw Object.assign(new Error('invalid-evidence'), { code: 'invalid-frame' }); };
export const equal = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
export const hash = async value => new Uint8Array(await crypto.subtle.digest('SHA-256', value));
export const random = length => crypto.getRandomValues(new Uint8Array(length));
export const hex = value => Array.from(value, b => b.toString(16).padStart(2, '0')).join('');
export async function peerId(key) { return hex((await hash(key)).slice(0, 16)); }
export function bytes(value, length) {
  if (typeof value !== 'string' || value.length > Math.ceil(length / 3) * 4 || !/^[a-z\d+/_-]*={0,2}$/i.test(value)) fail();
  let result;
  try { result = Uint8Array.from(atob(value.replaceAll('-', '+').replaceAll('_', '/')), c => c.charCodeAt(0)); } catch { fail(); }
  if (result.length !== length) fail();
  return result;
}
export const id = v => typeof v === 'string' && /^[A-Za-z0-9_=-]{1,128}$/.test(v);
export const integer = (v, min = 0, max = Number.MAX_SAFE_INTEGER) => Number.isSafeInteger(v) && v >= min && v <= max;
export const label = v => typeof v === 'string' && /^[a-z0-9][a-z0-9/:._-]{0,63}$/.test(v);
export const utf8 = text => encoder.encode(text);
export async function verify(key, signature, message) {
  try {
    if (key.length !== 32 || signature.length !== 64) return false;
    let y = 0n;
    for (let i = 31; i >= 0; i--) y = (y << 8n) | BigInt(i === 31 ? key[i] & 127 : key[i]);
    const p = (1n << 255n) - 19n;
    if ([0n, 1n, p - 1n, 2707385501144840649318225287225658788936804267575313519463743609750303402022n,
      55188659117513257062467267217118295137698188065244968500265048394206261417927n].includes(y % p)) return false;
    const imported = await crypto.subtle.importKey('raw', key, 'Ed25519', false, ['verify']);
    return await crypto.subtle.verify('Ed25519', imported, signature, message);
  } catch { return false; }
}
export const sign = async (key, message) => new Uint8Array(await crypto.subtle.sign('Ed25519', key, message));
export function attestation(value) {
  if (!value || value.domain !== 'intragram/attestation/v1' ||
      !['deliveryCommitted', 'burnTriggered', 'cleanupCompleted', 'cleanupFailed'].includes(value.k) ||
      !id(value.e) || !id(value.s) || value.a != null && !id(value.a) || value.cp != null && !id(value.cp) ||
      !label(value.p) || !label(value.o) || !integer(value.t)) fail();
  bytes(value.pk, 32); bytes(value.c, 32); bytes(value.n, 16); bytes(value.sg, 64);
  if (value.ck != null) bytes(value.ck, 32);
  return value;
}
export function attestationBytes(a) {
  attestation(a);
  return encode([a.domain, a.k, a.e, a.s, a.a || '', a.pk, a.cp || '', a.ck || '', a.c, a.p, a.o, a.n, a.t]);
}
export async function verifyAttestation(a) {
  try {
    if (a.ck != null && await peerId(bytes(a.ck, 32)) !== a.cp) return false;
    return await verify(bytes(a.pk, 32), bytes(a.sg, 64), attestationBytes(a));
  } catch { return false; }
}
export function credential(c) {
  const text = (v, max) => typeof v === 'string' && v.trim() && utf8(v).length <= max;
  if (!c || !id(c.id) || !id(c.iss) || !text(c.org, 96) || !text(c.dept, 96) || !text(c.role, 64) ||
      !label(c.pol) || !integer(c.iat) || !integer(c.exp) || c.exp <= c.iat ||
      typeof c.snap !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(c.snap)) fail();
  bytes(c.ik, 32); bytes(c.sk, 32); bytes(c.sg, 64);
  return c;
}
export function credentialBytes(c) {
  credential(c);
  return encode(['intragram/org-credential/v1', c.id, c.iss, c.ik, c.sk, c.org, c.dept, c.role, c.pol, c.iat, c.exp, c.snap]);
}
export async function credentialDigest(c) {
  return b64(await hash(new Uint8Array([...credentialBytes(c), ...bytes(c.sg, 64)])));
}
export function validateEvidenceControl(c) {
  if (!c || typeof c !== 'object') fail();
  switch (c.k) {
    case 'identity': bytes(c.pk, 32); bytes(c.sg, 64); break;
    case 'attestation': attestation(c.value); break;
    case 'org-credential':
      if (c.credential != null) {
        credential(c.credential); bytes(c.credentialDigest, 32); bytes(c.pop, 64);
        if (c.policy !== c.credential.pol) fail();
      }
      break;
    default: fail();
  }
  return c;
}
