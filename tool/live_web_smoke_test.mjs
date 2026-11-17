// Smoke test of the deployed web app (no deployment, read-only against the public site).
// WEB_BASE_URL is the landing page, for example https://gnoyx2.github.io/Intragram/ . Two isolated
// Chromium contexts connect through the public page: codes, security code, text both ways, a file each
// way byte-exact, a reload. Every request must stay on the site's origin; no console error, no 4xx/5xx.
import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const base = new URL(process.env.WEB_BASE_URL || 'https://gnoyx2.github.io/Intragram/');
assert.ok(base.pathname.endsWith('/'), 'WEB_BASE_URL must end with /');
const output = process.env.WEB_QA_OUTPUT_DIR || await mkdtemp(path.join(tmpdir(), 'intragram-live-smoke-'));
await mkdir(output, { recursive: true });
const errors = [], failures = [], foreign = [];
const sha = b => createHash('sha256').update(b).digest('hex');
const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const button = (page, name) => page.getByRole('button', { name: new RegExp(`^${esc(name)}(?: ${esc(name)})?$`) });
const fill = async (page, field, value) => { await field.focus(); await page.waitForTimeout(150); await page.keyboard.press('ControlOrMeta+A'); await page.keyboard.insertText(value); await page.waitForTimeout(100); };
const readCode = async page => { await button(page, 'Copy code').click(); const v = await page.evaluate(() => navigator.clipboard.readText()); assert.ok(v.startsWith('IGW1.')); return v; };
const message = (page, text) => page.getByLabel(text, { exact: false });
const composer = page => page.getByRole('textbox', { name: 'Message', exact: true });
const send = async (page, text) => { await page.bringToFront(); await fill(page, composer(page), text); await page.keyboard.press('Enter'); };
const tile = (page, name) => page.getByRole('group', { name: new RegExp(esc(name)) });
const log = msg => console.log('live smoke: ' + msg);
const dump = async (page, name) => {
  await writeFile(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
  await page.screenshot({ path: path.join(output, name + '.png') });
};
let browser;

function watch(page, name) {
  // 대화가 있는 새로고침은 앱이 브라우저 확인을 띄움: 그 확인만 수락 (나머지 대화상자는 기본처럼 닫음)
  page.on('dialog', d => d.type() === 'beforeunload' ? d.accept() : d.dismiss());
  page.on('pageerror', e => errors.push(`${name}: ${e.message}`));
  page.on('console', m => { if (m.type() === 'error') errors.push(`${name}: ${m.text()}`); });
  page.on('request', r => { const u = r.url(); if (!u.startsWith(base.origin + '/') && !u.startsWith('blob:') && !u.startsWith('data:')) foreign.push(u); });
  page.on('response', r => { if (r.status() >= 400) failures.push(`${r.status()} ${r.url()}`); });
}
async function context(name) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, locale: 'en-US', acceptDownloads: true });
  await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: base.origin });
  const page = await ctx.newPage();
  page.setDefaultTimeout(30000);
  watch(page, name);
  return page;
}
async function ready(page) {
  await page.locator('flt-semantics-placeholder').waitFor({ timeout: 60000 });
  await page.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await page.getByRole('heading', { name: /^Intragram/ }).waitFor({ timeout: 60000 });
  await page.locator('#app-loading').waitFor({ state: 'detached' });
}
async function link(host, guest) {
  await host.bringToFront();
  await button(host, 'Encrypted app–web connection').first().click();
  await button(host, 'Create invitation code').click();
  await host.getByRole('textbox', { name: 'Your connection code', exact: true }).waitFor();
  const offer = await readCode(host);
  await guest.bringToFront();
  await button(guest, 'Encrypted app–web connection').first().click();
  await button(guest, 'Join with a code').click();
  await fill(guest, guest.getByRole('textbox', { name: 'Their invitation code', exact: true }), offer);
  await button(guest, 'Create response code').click();
  await guest.getByRole('textbox', { name: 'Your connection code', exact: true }).waitFor();
  const response = await readCode(guest);
  await button(guest, 'Open conversation').click();
  await host.bringToFront();
  await fill(host, host.getByRole('textbox', { name: 'Their response code', exact: true }), response);
  await button(host, 'Connect').click();
}
async function transfer(from, to, name, bytes) {
  const file = path.join(output, name);
  await writeFile(file, bytes);
  await from.bringToFront();
  const [chooser] = await Promise.all([from.waitForEvent('filechooser'), button(from, 'Send a file').last().click()]);
  await chooser.setFiles(file);
  await to.bringToFront();
  await tile(to, name).getByRole('button', { name: 'Accept', exact: true }).click();
  const download = to.waitForEvent('download');
  await tile(to, name).getByRole('button', { name: 'Save to device', exact: true }).click();
  assert.equal(sha(await readFile(await (await download).path())), sha(bytes), `${name} arrives byte-exact`);
}

try {
  browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH });

  // Landing -> /web/ -> /web/app/ keeps only the allowed preferences.
  const landing = await context('L');
  const first = await landing.goto(base.href);
  assert.equal(first.status(), 200, 'landing page');
  await landing.locator('a[data-web-link]').first().click();
  await landing.waitForURL(url => new URL(url).pathname === base.pathname + 'web/app/', { timeout: 60000 });
  await ready(landing);
  await dump(landing, 'landing-to-app');
  log('landing -> /web/ -> /web/app/ opened the app');

  const a = await context('A'), b = await context('B');
  for (const page of [a, b]) { await page.goto(new URL('web/app/?lang=en', base).href); await ready(page); }
  await link(a, b);
  for (const page of [a, b]) {
    await page.bringToFront();
    await button(page, 'Check security code').click();
    await button(page, 'They match').click();
  }
  for (const page of [a, b]) await button(page, 'Security code verified').waitFor();
  log('two browsers connected with IGW1 codes and confirmed the security code');

  await send(a, '공개 주소 확인 👋 from A');
  await b.bringToFront(); await message(b, '공개 주소 확인 👋 from A').first().waitFor();
  await send(b, 'Reply from B');
  await a.bringToFront(); await message(a, 'Reply from B').first().waitFor();
  log('text both ways');

  await transfer(a, b, 'live-a-to-b.bin', randomBytes(256 * 1024));
  await transfer(b, a, 'live-b-to-a.bin', randomBytes(64 * 1024 + 7));
  await dump(b, 'after-files');
  log('a file each way, SHA-256 equal after saving');

  await b.reload();
  await ready(b);
  log('reload opens the app again');

  assert.deepEqual(errors, [], 'no console or page errors');
  assert.deepEqual(failures, [], 'no 4xx/5xx responses');
  assert.deepEqual(foreign, [], 'no request outside ' + base.origin);
  console.log('PASS: live web smoke on ' + base.href + ' Artifacts: ' + output);
} catch (error) {
  console.error('live smoke failure. Errors: ' + JSON.stringify(errors) + ' Failures: ' + JSON.stringify(failures) + ' Foreign: ' + JSON.stringify(foreign));
  throw error;
} finally {
  await browser?.close();
}
