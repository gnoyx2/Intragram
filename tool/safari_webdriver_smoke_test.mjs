// Shared Flutter web in the real Safari (safaridriver, W3C WebDriver over fetch) against Chromium:
// Safari invites and Chromium answers, then the reverse, the same security code on both sides,
// text both ways and a file each way byte-exact, no request outside the page origin and no ICE
// server. WEB_APP_URL is the app page, for example http://127.0.0.1:8765/web/app/ or
// https://gnoyx2.github.io/Intragram/web/app/ . Safari needs Settings > Developer > Allow remote
// automation. Safari runs in its own automation window; its saves are read from the Blob the save
// button hands to the browser, because WebDriver cannot answer Safari's download prompt. Keep that
// window in front during the run: covered or moved to the Stage Manager strip, Safari stops drawing.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const app = new URL(process.env.WEB_APP_URL || 'http://127.0.0.1:8765/web/app/');
assert.ok(app.pathname.endsWith('/'), 'WEB_APP_URL must end with /');
const page = new URL('?lang=en', app).href;
const port = Number(process.env.SAFARIDRIVER_PORT || 4447);
const output = process.env.WEB_QA_OUTPUT_DIR || await mkdtemp(path.join(tmpdir(), 'intragram-safari-qa-'));
await mkdir(output, { recursive: true });
const ELEMENT = 'element-6066-11e4-a52e-4f735466cecf';
const errors = [], failures = [], foreign = [], evidence = [];
const sha = b => createHash('sha256').update(b).digest('hex');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const log = m => console.log('safari QA: ' + m);
let driver, sid, browser;

async function wd(method, route, body) {
  const res = await fetch(`http://127.0.0.1:${port}/session${route}`, {
    method, headers: { 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`${method} ${route}: ${json.value?.error} ${json.value?.message}`);
  return json.value;
}
const s = (method, route, body) => wd(method, `/${sid}${route}`, body);
const run = (script, ...args) => s('POST', '/execute/sync', { script, args });
const runAsync = (script, ...args) => s('POST', '/execute/async', { script, args });
async function until(what, fn, timeout = 30000) {
  const end = Date.now() + timeout;
  for (;;) {
    const value = await fn();
    if (value) return value;
    if (Date.now() > end) throw new Error('timed out: ' + what);
    await sleep(200);
  }
}

// 페이지 안 훅: 파일 선택창 대신 준비한 File 넣기, 저장 Blob 보관, ICE 설정·후보·콘솔 오류 기록
const HOOKS = `if (window.__qa) return true;
const qa = window.__qa = { saved: {}, pending: null, ice: [], candidates: [], errors: [] };
const blobs = new Map(), objectUrl = URL.createObjectURL;
URL.createObjectURL = function (o) { const u = objectUrl.call(URL, o); if (o instanceof Blob) blobs.set(u, o); return u; };
const anchorClick = HTMLAnchorElement.prototype.click;
HTMLAnchorElement.prototype.click = function () {
  if (this.download && blobs.has(this.href)) { qa.saved[this.download] = blobs.get(this.href); return; }
  return anchorClick.call(this);
};
const inputClick = HTMLInputElement.prototype.click;
HTMLInputElement.prototype.click = function () {
  if (this.type !== 'file' || !qa.pending) return inputClick.call(this);
  const dt = new DataTransfer(); dt.items.add(qa.pending); qa.pending = null; this.files = dt.files;
  setTimeout(() => this.dispatchEvent(new Event('change', { bubbles: true })), 0);
};
const PC = window.RTCPeerConnection;
window.RTCPeerConnection = class extends PC { constructor(config, ...rest) { super(config, ...rest);
  qa.ice.push(JSON.stringify(config?.iceServers ?? []));
  this.addEventListener('icecandidate', e => { if (e.candidate?.candidate) qa.candidates.push(e.candidate.candidate); }); } };
const consoleError = console.error;
console.error = function (...a) { qa.errors.push(a.map(String).join(' ')); return consoleError.apply(console, a); };
window.addEventListener('error', e => qa.errors.push(String(e.message)));
window.addEventListener('unhandledrejection', e => qa.errors.push(String(e.reason)));
return true;`;
const FIND_BUTTON = `const [name, last, scope] = arguments;
const root = scope ? [...document.querySelectorAll('flt-semantics[role="group"]')].find(g => (g.getAttribute('aria-label') || '').includes(scope)) : document;
if (!root) return null;
const all = [...root.querySelectorAll('flt-semantics[role="button"]')].filter(e => { const t = e.textContent.trim(); return t === name || t === name + ' ' + name; });
return (last ? all[all.length - 1] : all[0]) || null;`;
const FIELD = `return document.querySelector('textarea[aria-label="' + arguments[0] + '"], input[aria-label="' + arguments[0] + '"]');`;

const sButton = (name, { last = false, scope = null, timeout } = {}) =>
  until(`Safari button ${name}`, () => run(FIND_BUTTON, name, last, scope), timeout);
async function sClick(name, options) {
  const el = await sButton(name, options);
  // semantics를 켠 Safari는 입력칸 포커스가 남은 채 누른 첫 클릭을 포커스 이동에만 씀
  const blurred = await run(`const a = document.activeElement; if (!a || !/^(INPUT|TEXTAREA)$/.test(a.tagName)) return false; a.blur(); return true;`);
  if (blurred) await sleep(300);
  try { await s('POST', `/element/${el[ELEMENT]}/click`, {}); } catch { await run('arguments[0].click();', el); }
}
async function sFill(label, text) {
  const el = await until(`Safari field ${label}`, () => run(FIELD, label));
  await run('arguments[0].focus();', el);
  await sleep(250);
  const filled = await run(`const [el, text] = arguments; el.focus(); el.select(); document.execCommand('insertText', false, text);
if (el.value !== text) { el.value = text; el.setSelectionRange(text.length, text.length); el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text })); }
return el.value === text;`, el, text);
  assert.ok(filled, `Safari filled ${label}`);
  await sleep(150);
}
async function sReadCode() {
  const el = await until('Safari code field', () => run(FIELD, 'Your connection code'));
  await run('arguments[0].focus();', el);
  return until('Safari code value', () => run(`const v = document.activeElement?.value || ''; return v.startsWith('IGW1.') ? v : null;`));
}
async function sSend(text) {
  await sFill('Message', text);
  const el = await run(FIELD, 'Message');
  await s('POST', `/element/${el[ELEMENT]}/value`, { text: '\uE007' });
}
const sSees = text => until(`Safari shows ${text}`, () =>
  run(`return [...document.querySelectorAll('[aria-label]')].some(e => e.getAttribute('aria-label').includes(arguments[0]));`, text));
const sHeading = source => until(`Safari heading ${source}`, () =>
  run(`return [...document.querySelectorAll('h1, h2, h3, [role="heading"]')].some(e => new RegExp(arguments[0]).test(e.textContent.trim()));`, source), 60000);
const sSas = () => until('Safari security code', () =>
  run(`const e = [...document.querySelectorAll('span, flt-semantics')].find(e => e.children.length === 0 && /^\\d \\d \\d, \\d \\d \\d$/.test(e.textContent.trim())); return e ? e.textContent.trim() : null;`));
async function sShot(name) { await writeFile(path.join(output, name + '.png'), Buffer.from(await s('GET', '/screenshot'), 'base64')); }
async function sOpen() {
  await s('POST', '/url', { url: page });
  await until('Safari semantics', () => run(`const p = document.querySelector('flt-semantics-placeholder'); if (!p) return false; p.click(); return true;`), 60000);
  await sHeading('^Intragram');
  await until('Safari loading screen gone', () => run(`return !document.getElementById('app-loading');`), 60000);
  await run(HOOKS);
}
async function sNetwork() {
  evidence.push(await run(`return { resources: performance.getEntriesByType('navigation').concat(performance.getEntriesByType('resource')).map(e => e.name), ice: window.__qa.ice, candidates: window.__qa.candidates, errors: window.__qa.errors };`));
}
async function sSendFile(name, bytes) {
  await run(`window.__qa.pending = new File([Uint8Array.from(atob(arguments[1]), c => c.charCodeAt(0))], arguments[0], { type: 'application/octet-stream' }); return true;`, name, bytes.toString('base64'));
  await sClick('Send a file', { last: true });
  await until('Safari picked ' + name, () => run('return window.__qa.pending === null;'));
}
async function sReceive(name, bytes) {
  await sClick('Accept', { scope: name });
  await sClick('Save to device', { scope: name, timeout: 60000 });
  const b64 = await until('Safari saved ' + name, () => runAsync(`const done = arguments[arguments.length - 1], blob = window.__qa.saved[arguments[0]];
if (!blob) return done(null);
blob.arrayBuffer().then(b => { const u = new Uint8Array(b); let s = ''; for (let i = 0; i < u.length; i += 32768) s += String.fromCharCode.apply(null, u.subarray(i, i + 32768)); done(btoa(s)); });`, name));
  assert.equal(sha(Buffer.from(b64, 'base64')), sha(bytes), `${name} byte-exact in Safari`);
}

const button = (p, name) => p.getByRole('button', { name: new RegExp(`^${esc(name)}(?: ${esc(name)})?$`) });
const fill = async (p, field, value) => { await field.focus(); await p.waitForTimeout(150); await p.keyboard.press('ControlOrMeta+A'); await p.keyboard.insertText(value); await p.waitForTimeout(100); };
const field = (p, name) => p.getByRole('textbox', { name, exact: true });
async function cOpen(name) {
  const p = await (await browser.newContext({ viewport: { width: 1280, height: 900 }, locale: 'en-US', acceptDownloads: true })).newPage();
  p.setDefaultTimeout(30000);
  p.on('pageerror', e => errors.push(`${name}: ${e.message}`));
  p.on('console', m => { if (m.type() === 'error') errors.push(`${name}: ${m.text()}`); });
  p.on('request', r => { const u = r.url(); if (!u.startsWith(app.origin + '/') && !u.startsWith('blob:') && !u.startsWith('data:')) foreign.push(u); });
  p.on('response', r => { if (r.status() >= 400) failures.push(`${r.status()} ${r.url()}`); });
  await p.goto(page);
  await p.locator('flt-semantics-placeholder').waitFor({ state: 'attached', timeout: 60000 });
  await p.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await p.getByRole('heading', { name: /^Intragram/ }).waitFor({ timeout: 60000 });
  await p.locator('#app-loading').waitFor({ state: 'detached' });
  return p;
}
async function cReadCode(p) {
  await field(p, 'Your connection code').focus();
  await p.waitForTimeout(300);
  const value = await p.evaluate(() => document.activeElement?.value ?? '');
  assert.ok(value.startsWith('IGW1.'), 'Chromium connection code');
  return value;
}
async function cSend(p, text) { await fill(p, field(p, 'Message'), text); await p.keyboard.press('Enter'); }
async function cSendFile(p, name, bytes) {
  const [chooser] = await Promise.all([p.waitForEvent('filechooser'), button(p, 'Send a file').last().click()]);
  await chooser.setFiles({ name, mimeType: 'application/octet-stream', buffer: bytes });
}
async function cReceive(p, name, bytes) {
  const tile = p.getByRole('group', { name: new RegExp(esc(name)) });
  await tile.getByRole('button', { name: 'Accept', exact: true }).click();
  const download = p.waitForEvent('download');
  await tile.getByRole('button', { name: 'Save to device', exact: true }).click();
  assert.equal(sha(await readFile(await (await download).path())), sha(bytes), `${name} byte-exact in Chromium`);
}
async function verify(p) {
  await sClick('Check security code');
  await sButton('They match');
  const safariCode = await sSas();
  await button(p, 'Check security code').click();
  await button(p, 'They match').waitFor();
  const chromiumCode = (await p.locator('body').ariaSnapshot()).match(/\d \d \d, \d \d \d/)?.[0];
  assert.ok(safariCode);
  assert.equal(safariCode, chromiumCode, 'the same security code in Safari and Chromium');
  await sClick('They match');
  await button(p, 'They match').click();
  await sButton('Security code verified');
  await button(p, 'Security code verified').waitFor();
}
const connected = async p => { await sHeading('encrypted · code not checked'); await p.getByRole('heading', { name: /encrypted · code not checked/ }).waitFor(); };

try {
  driver = spawn('safaridriver', ['-p', String(port)], { stdio: 'ignore' });
  await until('safaridriver', async () => { try { return (await fetch(`http://127.0.0.1:${port}/status`)).ok; } catch { return false; } }, 10000);
  const session = await wd('POST', '', { capabilities: { alwaysMatch: { browserName: 'safari' } } });
  sid = session.sessionId;
  const version = `Safari ${session.capabilities.browserVersion}`;
  await s('POST', '/timeouts', { script: 60000, pageLoad: 120000, implicit: 0 });
  await s('POST', '/window/rect', { width: 1280, height: 900 });
  browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH });

  // 1. Safari invites, Chromium answers.
  await sOpen();
  const c = await cOpen('C');
  await sClick('Encrypted app–web connection');
  await sClick('Create invitation code');
  const offer = await sReadCode();
  await button(c, 'Encrypted app–web connection').first().click();
  await button(c, 'Join with a code').click();
  await fill(c, field(c, 'Their invitation code'), offer);
  await button(c, 'Create response code').click();
  const answer = await cReadCode(c);
  await button(c, 'Open conversation').click();
  await sFill('Their response code', answer);
  await sClick('Connect');
  await connected(c);
  await verify(c);
  log(`${version} invitation, Chromium response, the same security code confirmed on both`);
  await sSend('Safari 안녕 👋 <b>markup</b>');
  await c.getByLabel('Safari 안녕 👋 <b>markup</b>', { exact: false }).first().waitFor();
  await cSend(c, 'Chromium reply 한글 ✅');
  await sSees('Chromium reply 한글 ✅');
  log('text both ways');
  const toChromium = randomBytes(300001), toSafari = randomBytes(200003);
  await sSendFile('safari-to-chromium.bin', toChromium);
  await cReceive(c, 'safari-to-chromium.bin', toChromium);
  await cSendFile(c, 'chromium-to-safari.bin', toSafari);
  await sReceive('chromium-to-safari.bin', toSafari);
  await sShot('safari-after-files');
  log('a file each way (Accept, Save to device), SHA-256 equal');
  await sNetwork();

  // 2. Chromium invites, Safari answers, in fresh pages.
  await sOpen();
  const c2 = await cOpen('C reverse');
  await button(c2, 'Encrypted app–web connection').first().click();
  await button(c2, 'Create invitation code').click();
  const offer2 = await cReadCode(c2);
  await sClick('Encrypted app–web connection');
  await sClick('Join with a code');
  await sFill('Their invitation code', offer2);
  await sClick('Create response code');
  const answer2 = await sReadCode();
  await sClick('Open conversation');
  await fill(c2, field(c2, 'Their response code'), answer2);
  await button(c2, 'Connect').click();
  await connected(c2);
  await verify(c2);
  await cSend(c2, 'Reverse direction 한글 from Chromium');
  await sSees('Reverse direction 한글 from Chromium');
  await sSend('Safari answer 👋');
  await c2.getByLabel('Safari answer 👋', { exact: false }).first().waitFor();
  await sShot('safari-reverse');
  log('Chromium invitation, Safari response, security code and text both ways');
  await sNetwork();

  const resources = evidence.flatMap(e => e.resources);
  const outside = resources.filter(u => !u.startsWith(app.origin + '/'));
  const ice = evidence.flatMap(e => e.ice), candidates = evidence.flatMap(e => e.candidates);
  await writeFile(path.join(output, 'safari-evidence.json'), JSON.stringify({ version, app: app.href, evidence }, null, 1));
  assert.deepEqual(outside, [], 'Safari loaded nothing outside ' + app.origin);
  assert.ok(ice.length > 0 && ice.every(i => i === '[]'), 'no ICE server in Safari');
  assert.ok(candidates.length > 0 && candidates.every(x => / typ host/.test(x)), 'Safari gathered host candidates only');
  assert.deepEqual(evidence.flatMap(e => e.errors), [], 'no Safari console or page errors');
  assert.deepEqual(errors, [], 'no Chromium console or page errors');
  assert.deepEqual(failures, [], 'no 4xx/5xx responses in Chromium');
  assert.deepEqual(foreign, [], 'Chromium requested nothing outside ' + app.origin);
  console.log(`PASS: ${version} <-> Chromium on ${app.href} (${resources.length} same-origin loads, ${candidates.length} host candidates). Artifacts: ${output}`);
} catch (error) {
  if (sid) {
    await sShot('safari-failure').catch(() => {});
    const state = await runAsync(`const done = arguments[arguments.length - 1]; let frames = 0; const f = () => { frames++; requestAnimationFrame(f); };
requestAnimationFrame(f); setTimeout(() => done({ visibility: document.visibilityState, focus: document.hasFocus(), frames }), 500);`).catch(() => null);
    console.error('Safari window: ' + JSON.stringify(state) + (state && !state.frames ? ' (no frames drawn: the window was covered or in the Stage Manager strip)' : ''));
  }
  console.error('safari QA failure. Chromium errors: ' + JSON.stringify(errors) + ' failures: ' + JSON.stringify(failures) + ' foreign: ' + JSON.stringify(foreign));
  throw error;
} finally {
  if (sid) await wd('DELETE', `/${sid}`).catch(() => {});
  driver?.kill();
  await browser?.close();
}
