// Check the raw authority before URL parsing, which normalizes octal and shortened IPv4.
export function parsePortalUrl(input) {
  const fail = () => { throw Object.assign(new Error('invalid-portal'), { code: 'invalid-portal' }); };
  if (typeof input !== 'string' || input.length > 2048) return fail();
  let raw = input.trim();
  if (raw.startsWith('IGA1.')) {
    if (!/^IGA1\.[A-Za-z0-9_-]+$/.test(raw)) return fail();
    try { raw = new TextDecoder('utf-8', { fatal: true }).decode(Uint8Array.from(atob(raw.slice(5).replaceAll('-', '+').replaceAll('_', '/')), c => c.charCodeAt(0))); }
    catch { return fail(); }
  }
  const match = /^http:\/\/(\[[0-9a-f:]+\]|[0-9.]+):([1-9]\d{0,4})\/?#t=([a-z\d_-]{43}=?)(?:&p=[a-f\d]{32})?$/i.exec(raw);
  if (!match || Number(match[2]) > 65535) return fail();
  const host = match[1];
  if (host.startsWith('[')) {
    if (!/^\[f[cd][a-f\d]{2}:/i.test(host)) return fail();
  } else {
    const parts = host.split('.');
    if (parts.length !== 4 || parts.some(p => !/^(0|[1-9]\d{0,2})$/.test(p) || +p > 255)) return fail();
    const [a, b] = parts.map(Number);
    if (!(a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 169 && b === 254))) return fail();
  }
  let url;
  try { url = new URL(raw); } catch { return fail(); }
  if (url.username || url.password || url.search || url.pathname !== '/' || (url.port ? Number(url.port) : 80) !== Number(match[2])) return fail();
  return url.href;
}
