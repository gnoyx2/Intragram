// Run after packaging and activating tool/web_entry.html locally; never deploys.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const root = path.resolve('docs');
const prefix = process.env.WEB_PACKAGE_PREFIX || '';
const output = process.env.WEB_QA_OUTPUT_DIR || 'work/web-package-browser';
await mkdir(output, { recursive: true });
const mime = { '.html': 'text/html', '.mjs': 'text/javascript', '.js': 'text/javascript', '.css': 'text/css', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.woff2': 'font/woff2', '.ttf': 'font/ttf' };
const server = createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (!url.pathname.startsWith(prefix + '/')) { res.writeHead(404).end(); return; }
  const route = url.pathname.slice(prefix.length);
  const file = path.resolve(root, '.' + route + (route.endsWith('/') ? 'index.html' : ''));
  if (!file.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
  try { const bytes = await readFile(file); res.writeHead(200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream' }); res.end(bytes); }
  catch { res.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
let browser;
const requests = [], errors = [], failures = [];
// A normal disk profile, not an incognito context: Chrome then also fetches the web app manifest.
const profile = await mkdtemp(path.join(tmpdir(), 'intragram-package-profile-'));
try {
  browser = await chromium.launchPersistentContext(profile, { executablePath: process.env.CHROME_PATH, headless: true, viewport: { width: 1440, height: 1000 } });
  const page = browser.pages()[0] ?? await browser.newPage();
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('request', r => requests.push(r.url()));
  page.on('response', r => { if (r.status() >= 400) failures.push(r.url()); });
  const entry = origin + prefix + '/web/?lang=ko&theme=dark&mode=portal&token=discard#secret';
  await page.goto(entry);
  await page.waitForURL(origin + prefix + '/web/app/?lang=ko&theme=dark&mode=portal');
  const ready = async () => {
    await page.locator('flt-semantics-placeholder').waitFor();
    await page.locator('flt-semantics-placeholder').evaluate(e => e.click());
    // mode=portal opens the shared connection dialog over the home screen, also after a reload.
    await page.getByRole('button', { name: /^새 연결 만들기/ }).waitFor();
    await page.locator('#app-loading').waitFor({ state: 'detached' });
    assert.ok((await page.locator('body').ariaSnapshot()).includes('앱·웹 암호화 연결'));
    await page.getByRole('button', { name: /^취소/ }).click();
    await page.getByRole('heading', { name: /^Intragram/ }).waitFor();
    assert.equal(await page.evaluate(() => document.documentElement.dataset.theme), 'dark');
    assert.ok((await page.locator('body').ariaSnapshot()).includes('암호화'));
  };
  await ready();
  await page.screenshot({ path: path.join(output, 'entry.png') });
  await page.reload();
  await ready();
  await writeFile(path.join(output, 'home.txt'), await page.locator('body').ariaSnapshot());
  assert.deepEqual(errors, []);
  assert.deepEqual(failures, []);
  assert.ok(requests.every(url => url.startsWith(origin + '/') || url.startsWith('blob:')));

  // 다른 출처의 페이지가 프레임에 넣으면 앱을 띄우지 않고 새 탭 링크만 보임 (정적 호스팅은 frame-ancestors 헤더를 못 넣음)
  const host = createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(`<!doctype html><title>host</title><iframe src="${origin + prefix}/web/app/?lang=ko" width="900" height="700"></iframe>`);
  });
  await new Promise(resolve => host.listen(0, '127.0.0.1', resolve));
  try {
    const outer = await browser.newPage(), framed = [], framedErrors = [];
    outer.on('request', r => framed.push(r.url()));
    outer.on('pageerror', e => framedErrors.push(e.message));
    outer.on('console', m => { if (m.type() === 'error') framedErrors.push(m.text()); });
    await outer.goto(`http://localhost:${host.address().port}/`);
    const frame = outer.frameLocator('iframe');
    const open = frame.getByRole('link', { name: /새 탭에서 열기/ });
    await open.waitFor();
    assert.equal(await open.getAttribute('href'), origin + prefix + '/web/app/?lang=ko');
    await outer.waitForTimeout(1500);
    assert.equal(await frame.locator('flutter-view, flt-glass-pane, flt-semantics-placeholder').count(), 0, 'no app inside a frame');
    assert.ok(!framed.some(url => url.endsWith('/main.dart.js')), 'the framed page never loads the app code');
    assert.deepEqual(framedErrors, []);
    await outer.screenshot({ path: path.join(output, 'framed.png') });
    await outer.close();
  } finally { await new Promise(resolve => host.close(resolve)); }
  const result = { pass: true, prefix, checks: ['entry redirect', 'preference whitelist', 'secret stripping', 'Korean dark shared home', 'direct app reload', 'first frame loader removal', 'local assets/CSP/no404/no external requests', 'no app inside a cross-origin frame'] };
  await writeFile(path.join(output, 'result.json'), JSON.stringify(result, null, 2));
  console.log('PASS web package browser: ' + JSON.stringify(result));
} finally { await browser?.close(); await rm(profile, { recursive: true, force: true }); await new Promise(resolve => server.close(resolve)); }
