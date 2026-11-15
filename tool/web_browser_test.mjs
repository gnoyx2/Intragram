// Optional real-browser QA. No production dependency: point PLAYWRIGHT_MODULE at
// an installed Playwright module and optionally CHROME_PATH at a Chromium binary.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, mkdir, mkdtemp } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';

const modulePath = process.env.PLAYWRIGHT_MODULE || 'playwright';
const { chromium } = await import(path.isAbsolute(modulePath) ? pathToFileURL(modulePath).href : modulePath);
const root = fileURLToPath(new URL('../docs/', import.meta.url));
const out = process.env.WEB_QA_OUTPUT_DIR || await mkdtemp(path.join(tmpdir(), 'intragram-web-qa-'));
await mkdir(out, { recursive: true });
const mime = { '.html': 'text/html', '.mjs': 'text/javascript', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png', '.jpg': 'image/jpeg' };
const server = createServer(async (request, response) => {
  try {
    const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname).replace(/^\/Intragram\//, '/');
    const file = path.resolve(root, '.' + pathname + (pathname.endsWith('/') ? 'index.html' : ''));
    if (!file.startsWith(root)) { response.writeHead(403).end(); return; }
    response.writeHead(200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    response.end(await readFile(file));
  } catch { response.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const url = origin + '/Intragram/web/lite.html?lang=ko';
let browser;
try {
  browser = await chromium.launch({ headless: true, ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}) });
  const one = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const two = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  const a = await one.newPage(), b = await two.newPage();
  const errors = [], requests = [];
  for (const page of [a, b]) {
    page.on('pageerror', e => errors.push(e.message));
    page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
    page.on('request', req => requests.push(req.url()));
  }
  await Promise.all([a.goto(url), b.goto(url)]);
  await a.locator('#mode-join').click();
  await a.locator('#invite-code').fill('not-an-invitation');
  await a.locator('#accept-offer').click();
  await a.locator('#error:visible').waitFor();
  assert.equal(await a.locator('#connection-status').getAttribute('data-state'), 'idle');
  const nativeUrl = 'http://192.168.1.2:7890#t=' + Buffer.alloc(32, 7).toString('base64url') + '=';
  await a.locator('#invite-code').fill('IGA1.' + Buffer.from(nativeUrl).toString('base64url'));
  await a.locator('#accept-offer').click();
  await a.locator('#error:visible').waitFor();
  assert.match(await a.locator('#error').innerText(), /HTTP/);
  assert.equal(new URL(a.url()).host, new URL(origin).host, 'legacy plaintext invitation must never navigate');
  await a.locator('#mode-create').click();
  for (const [width, height] of [[1440, 900], [1024, 768], [768, 1024], [390, 844]]) {
    await a.setViewportSize({ width, height });
    assert.ok(await a.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `no overflow at ${width}`);
    await a.screenshot({ path: path.join(out, `web-${width}.png`), fullPage: true });
  }
  await a.setViewportSize({ width: 1440, height: 900 });
  await a.locator('#create-offer').click();
  await a.waitForFunction(() => document.querySelector('#local-code').value.startsWith('IGW1.'));
  const offer = await a.locator('#local-code').inputValue();
  await b.locator('#mode-join').click(); await b.locator('#invite-code').fill(offer); await b.locator('#accept-offer').click();
  await b.waitForFunction(() => document.querySelector('#local-code').value.startsWith('IGW1.'));
  const answer = await b.locator('#local-code').inputValue();
  await a.locator('#answer-code').fill(offer); await a.locator('#accept-answer').click();
  await a.locator('#error:visible').waitFor();
  assert.equal(await a.locator('#connection-status').getAttribute('data-state'), 'waiting', 'wrong code type can be corrected');
  await a.locator('#answer-code').fill(answer); await a.locator('#accept-answer').click();
  await Promise.all([a.locator('#chat:visible').waitFor(), b.locator('#chat:visible').waitFor()]);
  assert.match(await a.locator('#verification-code').innerText(), /^\d{6}$/);
  assert.equal(await a.locator('#verification-code').innerText(), await b.locator('#verification-code').innerText());
  const text = '안녕하세요. <script>실행되지 않는 메시지</script> & "한글"';
  await a.locator('#message-input').fill(text); await a.locator('#send').click();
  await b.getByText(text, { exact: true }).waitFor();
  await b.locator('#message-input').fill('Browser reply: 연결 성공'); await b.locator('#message-input').press('Enter');
  await a.getByText('Browser reply: 연결 성공', { exact: true }).waitFor();
  assert.equal(await b.locator('#messages script').count(), 0);
  await a.locator('#language').selectOption('en'); await a.locator('#theme').selectOption('dark');
  assert.equal(await a.locator('#connection-status').getAttribute('data-state'), 'connected');
  await a.locator('#language').selectOption('ko');

  const payload = Buffer.alloc(256 * 1024 + 37);
  for (let i = 0; i < payload.length; i++) payload[i] = i % 251;
  await a.locator('#file-input').setInputFiles({ name: '검증 파일.bin', mimeType: 'application/octet-stream', buffer: payload });
  await b.getByRole('button', { name: '받기', exact: true }).click();
  const save = b.getByRole('link', { name: '파일 저장', exact: true });
  await save.waitFor();
  const received = b.waitForEvent('download'); await save.click();
  assert.deepEqual(await readFile(await (await received).path()), payload, 'all chunked file bytes match');
  await a.locator('.transfer[data-state="complete"]').waitFor();
  await b.locator('#file-input').setInputFiles({ name: 'empty.txt', mimeType: 'text/plain', buffer: Buffer.alloc(0) });
  await a.getByRole('button', { name: '받기', exact: true }).click();
  const empty = a.waitForEvent('download'); await a.getByRole('link', { name: '파일 저장', exact: true }).click();
  assert.equal((await readFile(await (await empty).path())).length, 0, 'empty file round trip');
  await a.locator('#file-input').setInputFiles({ name: 'decline.txt', mimeType: 'text/plain', buffer: Buffer.from('decline') });
  await b.getByRole('button', { name: '거절', exact: true }).click();
  await a.locator('.transfer[data-state="rejected"]').waitFor();
  await a.locator('#file-input').setInputFiles({ name: 'cancel.txt', mimeType: 'text/plain', buffer: Buffer.from('cancel') });
  await a.getByRole('button', { name: '취소', exact: true }).click();
  await b.locator('.transfer[data-state="cancelled"]').waitFor();
  await a.screenshot({ path: path.join(out, 'chat-dark-1440.png'), fullPage: true });
  await b.setViewportSize({ width: 390, height: 844 });
  assert.ok(await b.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  const sendBox = await b.locator('#send').boundingBox();
  assert.ok(sendBox.y + sendBox.height <= 844, 'mobile composer stays visible');
  await b.screenshot({ path: path.join(out, 'chat-light-390.png'), fullPage: true });
  await b.locator('#theme').selectOption('dark');
  await b.screenshot({ path: path.join(out, 'chat-dark-390.png'), fullPage: true });
  await a.locator('#reset').click(); await a.locator('#keep-session').click();
  assert.equal(await a.locator('#connection-status').getAttribute('data-state'), 'connected');
  await a.locator('#reset').click(); await a.locator('#end-session').click();
  assert.equal(await a.locator('.message').count(), 0);
  assert.equal(await a.locator('.transfer').count(), 0);
  assert.equal(await a.locator('#local-code').inputValue(), '');
  await b.waitForFunction(() => document.querySelector('#connection-status').dataset.state === 'closed');
  assert.equal(await b.locator('#send').isEnabled(), false);
  assert.equal(await b.getByRole('link', { name: '파일 저장', exact: true }).count(), 1, 'peer disconnect retains completed unsaved downloads');
  assert.deepEqual(errors, [], 'no runtime or CSP errors');
  assert.ok(requests.every(request => request.startsWith(origin + '/') || request.startsWith('blob:')), 'no external requests');

  const unsupported = await browser.newContext();
  await unsupported.addInitScript(() => { window.RTCPeerConnection = undefined; });
  const old = await unsupported.newPage(); await old.goto(url);
  await old.locator('#error:visible').waitFor();
  assert.equal(await old.locator('#create-offer').isEnabled(), false);

  // 다른 출처의 페이지가 프레임에 넣으면 동작하지 않고 새 탭 링크만 보임 (보이지 않는 프레임으로 클릭을 유도하지 못함)
  const host = createServer((request, response) => {
    response.writeHead(200, { 'Content-Type': 'text/html' });
    response.end(`<!doctype html><title>host</title><iframe src="${url}" width="900" height="700"></iframe>`);
  });
  await new Promise(resolve => host.listen(0, '127.0.0.1', resolve));
  try {
    const outer = await (await browser.newContext()).newPage(), framedErrors = [];
    outer.on('pageerror', e => framedErrors.push(e.message));
    outer.on('console', msg => { if (msg.type() === 'error') framedErrors.push(msg.text()); });
    await outer.goto(`http://localhost:${host.address().port}/`);
    const frame = outer.frameLocator('iframe');
    const open = frame.getByRole('link', { name: /새 탭에서 열기/ });
    await open.waitFor();
    assert.equal(await open.getAttribute('href'), url);
    assert.equal(await frame.locator('button, input, select, textarea').count(), 0, 'no controls inside a frame');
    assert.deepEqual(framedErrors, [], 'the framed page stops quietly');
  } finally { await new Promise(resolve => host.close(resolve)); }
  console.log(`PASS: real WebRTC in isolated browser contexts; legacy plaintext invitation rejection; text both ways; exact multichunk and empty files; reject/cancel; reset/disconnect; KO/EN and themes; 4 viewport widths; no external requests; refuses to run inside another site's frame. Screenshots: ${out}`);
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
}
