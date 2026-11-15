import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parsePortalUrl } from '../docs/web/portal.mjs';

const token = Buffer.alloc(32, 7).toString('base64url') + '=';
const wrap = url => 'IGA1.' + Buffer.from(url).toString('base64url');
const rejects = input => assert.throws(() => parsePortalUrl(input), error => error.code === 'invalid-portal', String(input));
for (const host of ['10.1.2.3', '172.16.0.1', '172.31.255.254', '192.168.1.5', '169.254.2.3', '[fd12:3456::1]']) {
  const raw = `http://${host}:7890#t=${token}`;
  assert.equal(parsePortalUrl(raw), new URL(raw).href);
  assert.equal(parsePortalUrl(wrap(raw)), new URL(raw).href, 'native Dart IGA1 format interoperates');
  assert.equal(parsePortalUrl(` ${raw} `), new URL(raw).href);
  assert.equal(parsePortalUrl(raw + '&p=' + 'a'.repeat(32)), new URL(raw + '&p=' + 'a'.repeat(32)).href);
}
assert.equal(parsePortalUrl(`http://192.168.1.2:80/#t=${token}`), `http://192.168.1.2/#t=${token}`);
assert.equal(parsePortalUrl(`http://10.0.0.1:65535/#t=${token.slice(0, -1)}`), `http://10.0.0.1:65535/#t=${token.slice(0, -1)}`);
for (const host of ['8.8.8.8', '127.0.0.1', '0.0.0.0', '172.15.0.1', '172.32.0.1', '100.64.0.1', '10.1', '010.0.0.1', '0xa000001', '167772161', '192.168.0.256', 'localhost', 'host.local', 'private.example', '[::1]', '[2001:db8::1]', '[fe80::1]', '[::ffff:192.168.1.1]']) {
  rejects(`http://${host}:7890/#t=${token}`);
  rejects(wrap(`http://${host}:7890/#t=${token}`));
}
for (const raw of [null, {}, '', 'IGA1.', 'IGA1._w', 'IGW1.abc', 'IGA1.' + 'a'.repeat(2048),
  `https://192.168.1.2:7890/#t=${token}`, `javascript:alert(1)`,
  `http://192.168.1.2:7890/path#t=${token}`, `http://192.168.1.2:7890/?q=1#t=${token}`,
  `http://192.168.1.2:7890/#t=short`, `http://192.168.1.2:7890/#t=${token}&url=https://example.com`,
  `http://192.168.1.2:7890/#t=${token}&p=bad`, `http://192.168.1.2:7890/#t=${token}&t=${token}`,
  `http://192.168.1.2:7890/#t=${token}%0a`, `http://user@192.168.1.2:7890/#t=${token}`,
  `http://192.168.1.2:7890@8.8.8.8:7890/#t=${token}`, `http://192.168.1.2\\@8.8.8.8:7890/#t=${token}`,
  `http://192.168.1.2:07890/#t=${token}`, `http://192.168.1.2:65536/#t=${token}`,
  `http://192.168.1.2:0/#t=${token}`, `http://192.168.1.2:7890/\n#t=${token}`,
]) rejects(raw);

const read = name => readFileSync(new URL('../' + name, import.meta.url), 'utf8');
const native = read('assets/web/css/theme.css'), web = read('docs/web/theme.css');
const blocks = text => [...text.matchAll(/:root[^{}]*\{([^}]+)\}/g)].map(match =>
  Object.fromEntries([...match[1].matchAll(/(--[\w-]+):\s*([^;]+);/g)].map(m => [m[1], m[2].trim()])));
const [nativeLight, nativeDark] = blocks(native), [webLight, webAutoDark, webDark] = blocks(web);
for (const [key, value] of Object.entries(nativeLight)) assert.equal(webLight[key], value, `native light ${key}`);
for (const [key, value] of Object.entries(nativeDark)) {
  assert.equal(webAutoDark[key], value, `native auto dark ${key}`);
  assert.equal(webDark[key], value, `native explicit dark ${key}`);
}
const html = read('docs/web/lite.html');
assert.match(html, /name="referrer" content="no-referrer"/);
assert.match(html, /script-src 'self'/);
assert.match(html, /href="\.\/theme.css"/);
const portalSource = read('docs/web/portal.mjs');
assert.doesNotMatch(portalSource, /\bfetch\(|\bWebSocket\(|\blocation\s*=/, 'parsing a native invite never requests or opens it');
console.log('web portal: native IGA1 + strict LAN URL/QR validation, no token navigation, native light/dark token parity passed');
