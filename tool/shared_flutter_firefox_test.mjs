// Shared Flutter web in the installed Firefox (WebDriver BiDi) against Chromium: both invitation
// directions, security code, text and files both ways (byte-exact), and a Firefox member in a
// Chromium-hosted group. Isolated browser profiles; QA code never changes app state.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const { chromium, firefox } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const firefoxPath = process.env.FIREFOX_PATH || '/Applications/Firefox.app/Contents/MacOS/firefox';
const root = path.resolve(process.env.SHARED_WEB_BUILD_DIR || fileURLToPath(new URL('../build/web/', import.meta.url)));
const output = process.env.WEB_QA_OUTPUT_DIR || await mkdtemp(path.join(tmpdir(), 'intragram-firefox-qa-'));
await mkdir(output, { recursive: true });
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.ttf': 'font/ttf', '.woff2': 'font/woff2' };
const server = createServer(async (req, res) => {
  const pathname = new URL(req.url, 'http://localhost').pathname;
  const file = path.resolve(root, '.' + pathname + (pathname.endsWith('/') ? 'index.html' : ''));
  if (!file.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
  try { const bytes = await readFile(file); res.writeHead(200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream' }); res.end(bytes); }
  catch { res.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const browsers = [], errors = [], failedRequests = [], requests = [];
const sha = b => createHash('sha256').update(b).digest('hex');
const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const button = (page, name) => page.getByRole('button', { name: new RegExp(`^${esc(name)}(?: ${esc(name)})?$`) });
const fill = async (page, field, value) => { await field.focus(); await page.waitForTimeout(150); await page.keyboard.press('ControlOrMeta+A'); await page.keyboard.insertText(value); await page.waitForTimeout(100); };
const codeField = page => page.getByRole('textbox', { name: 'Your connection code', exact: true });
const message = (page, text) => page.getByLabel(text, { exact: false });
const composer = page => page.getByRole('textbox', { name: 'Message', exact: true });
const send = async (page, text) => { await page.bringToFront(); await fill(page, composer(page), text); await page.keyboard.press('Enter'); };
const dump = async (page, name) => {
  await writeFile(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
  await page.screenshot({ path: path.join(output, name + '.png') });
};
// The code is read from the focused read-only field, as a person selecting it would: Firefox
// gives pages no silent clipboard read, and Flutter fills the field's DOM text only on focus.
async function readCode(page) {
  await codeField(page).focus();
  await page.waitForTimeout(300);
  const value = await page.evaluate(() => document.activeElement?.value ?? '');
  assert.ok(value.startsWith('IGW1.'), 'connection code field');
  return value;
}
async function open(kind, name) {
  const type = kind === 'firefox' ? firefox : chromium;
  const browser = kind === 'firefox'
    ? await type.launch({ channel: 'moz-firefox', executablePath: firefoxPath, headless: true })
    : await type.launch({ headless: true, executablePath: process.env.CHROME_PATH });
  browsers.push(browser);
  const page = await (await browser.newContext({ viewport: { width: 1280, height: 900 }, locale: 'en-US', acceptDownloads: true })).newPage();
  page.setDefaultTimeout(30000);
  page.on('pageerror', e => errors.push(`${name}: ${e.message}`));
  page.on('console', m => { if (m.type() === 'error') errors.push(`${name}: ${m.text()}`); });
  page.on('request', r => requests.push(r.url()));
  page.on('response', r => { if (r.status() >= 400) failedRequests.push(r.url()); });
  await page.goto(origin + '/?lang=en');
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached' });
  await page.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await page.getByRole('heading', { name: /^Intragram/ }).waitFor();
  await page.locator('#app-loading').waitFor({ state: 'detached' });
  return page;
}
async function link(host, guest, add = false) {
  await host.bringToFront();
  if (add) {
    await button(host, 'More').last().click();
    await host.getByRole('menuitem', { name: 'Add people', exact: true }).click();
    await button(host, 'Add').waitFor();
    await button(host, 'Encrypted app–web connection').last().click();
  } else {
    await button(host, 'Encrypted app–web connection').first().click();
  }
  await button(host, 'Create invitation code').click();
  const offer = await readCode(host);
  await guest.bringToFront();
  await button(guest, 'Encrypted app–web connection').first().click();
  await button(guest, 'Join with a code').click();
  await fill(guest, guest.getByRole('textbox', { name: 'Their invitation code', exact: true }), offer);
  await button(guest, 'Create response code').click();
  const response = await readCode(guest);
  await button(guest, 'Open conversation').click();
  await host.bringToFront();
  await fill(host, host.getByRole('textbox', { name: 'Their response code', exact: true }), response);
  await button(host, 'Connect').click();
}
async function verify(a, b) {
  const codes = [];
  for (const p of [a, b]) {
    await p.bringToFront();
    await button(p, 'Check security code').click();
    await button(p, 'They match').waitFor();
    codes.push((await p.locator('body').ariaSnapshot()).match(/\d \d \d, \d \d \d/)?.[0]);
    await button(p, 'They match').click();
  }
  assert.ok(codes[0]); assert.equal(codes[0], codes[1]);
  for (const p of [a, b]) await button(p, 'Security code verified').waitFor();
}
async function transfer(from, to, name, bytes) {
  await from.bringToFront();
  const [chooser] = await Promise.all([from.waitForEvent('filechooser'), button(from, 'Send a file').last().click()]);
  await chooser.setFiles({ name, mimeType: 'application/octet-stream', buffer: bytes });
  await to.bringToFront();
  const tile = to.getByRole('group', { name: new RegExp(esc(name)) });
  await tile.getByRole('button', { name: 'Accept', exact: true }).click();
  const download = to.waitForEvent('download');
  await tile.getByRole('button', { name: 'Save to device', exact: true }).click();
  assert.equal(sha(await readFile(await (await download).path())), sha(bytes), name);
}

try {
  const c = await open('chromium', 'C'), f = await open('firefox', 'F');
  assert.match(await f.evaluate(() => navigator.userAgent), /Firefox\/\d+/);

  await link(c, f);
  for (const p of [c, f]) await p.getByRole('heading', { name: /encrypted · code not checked/ }).waitFor();
  await verify(c, f);
  console.log('firefox QA: Chromium invitation, Firefox response, same security code confirmed on both');
  await send(f, 'Firefox 안녕 👋 <b>markup</b>');
  await c.bringToFront(); await message(c, 'Firefox 안녕 👋 <b>markup</b>').waitFor();
  await send(c, 'Chromium reply 한글 ✅');
  await f.bringToFront(); await message(f, 'Chromium reply 한글 ✅').waitFor();
  await transfer(f, c, 'firefox-to-chromium.bin', Buffer.from(Array.from({ length: 300001 }, (_, i) => (i * 7) % 256)));
  await transfer(c, f, 'chromium-to-firefox.bin', Buffer.from(Array.from({ length: 200003 }, (_, i) => (i * 13) % 256)));
  await dump(f, 'firefox-chat');
  console.log('firefox QA: text both ways and files both ways (Accept, Save to device) byte-exact');

  // Lanes: Firefox sends a big and a small file back to back; the small one finishes while the
  // big one still flows (two files at once, as in the app), and both arrive byte-exact.
  const bigPath = path.join(output, 'firefox-big.bin');
  const big = Buffer.from(Array.from({ length: 32 << 20 }, (_, i) => (i * 31 + 7) % 251));
  await writeFile(bigPath, big);
  const small = Buffer.from('Firefox small file overtakes the big one\n');
  for (const file of [bigPath, { name: 'firefox-small.txt', mimeType: 'text/plain', buffer: small }]) {
    await f.bringToFront();
    const [chooser] = await Promise.all([f.waitForEvent('filechooser'), button(f, 'Send a file').last().click()]);
    await chooser.setFiles(file);
  }
  await c.bringToFront();
  const tile = name => c.getByRole('group', { name: new RegExp(esc(name)) });
  await tile('firefox-big.bin').getByRole('button', { name: 'Accept', exact: true }).click();
  await tile('firefox-small.txt').getByRole('button', { name: 'Accept', exact: true }).click();
  await tile('firefox-small.txt').getByRole('button', { name: 'Save to device', exact: true }).waitFor();
  assert.equal(await tile('firefox-big.bin').getByRole('button', { name: 'Save to device', exact: true }).count(), 0,
    'the big file still flows when the small one is done');
  const saved = async name => { const dl = c.waitForEvent('download'); await tile(name).getByRole('button', { name: 'Save to device', exact: true }).click(); return readFile(await (await dl).path()); };
  assert.deepEqual(await saved('firefox-small.txt'), small);
  await tile('firefox-big.bin').getByRole('button', { name: 'Save to device', exact: true }).waitFor({ timeout: 180000 });
  assert.equal(sha(await saved('firefox-big.bin')), sha(big));
  console.log('firefox QA: two files at once Firefox -> Chromium, small done first, 32 MiB byte-exact');

  // Reverse direction in a fresh pair: Firefox invites, Chromium answers.
  const c2 = await open('chromium', 'C2'), f2 = await open('firefox', 'F2');
  await link(f2, c2);
  for (const p of [f2, c2]) await p.getByRole('heading', { name: /encrypted · code not checked/ }).waitFor();
  await verify(f2, c2);
  await send(c2, 'Reverse direction text');
  await f2.bringToFront(); await message(f2, 'Reverse direction text').waitFor();
  console.log('firefox QA: Firefox invitation, Chromium response, security code and text');

  // Firefox joins a Chromium-hosted group as the second member.
  await link(c, c2, true);
  await send(c2, 'Group text relayed to Firefox');
  await f.bringToFront(); await message(f, 'Group text relayed to Firefox').waitFor();
  await send(f, 'Firefox member reply');
  await c2.bringToFront(); await message(c2, 'Firefox member reply').waitFor();
  await dump(f, 'firefox-group');
  console.log('firefox QA: Firefox member in a Chromium-hosted group, relayed text both ways');

  assert.deepEqual(errors, []);
  assert.deepEqual(failedRequests, []);
  assert.ok(requests.every(url => url.startsWith(origin + '/') || url.startsWith('blob:') || url.startsWith('data:')), 'no outside requests');
  console.log('PASS: shared Flutter web in Firefox ' + (await f.evaluate(() => navigator.userAgent.match(/Firefox\/[\d.]+/)[0])) + ' <-> Chromium. Artifacts: ' + output);
} catch (error) {
  console.log('errors: ' + JSON.stringify(errors) + '\nfailed: ' + JSON.stringify(failedRequests));
  throw error;
} finally {
  for (const b of browsers) await b.close().catch(() => {});
  await new Promise(resolve => server.close(resolve));
}
