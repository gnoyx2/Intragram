// Shared Flutter web in a really hidden tab. Opens a VISIBLE Chromium window.
// Playwright keeps every page it launches "visible and focused" (focus emulation, and launch flags that
// stop Chromium from hiding covered windows), so the background auto-lock of a PIN vault cannot be
// reached in the other browser tests. Here page A runs in a browser started the way a user starts it
// and Playwright attaches without its overrides (noDefaults): a tab switch then sets document.hidden.
// Checked: a short absence changes nothing, one minute in the background locks the vault before the
// page paints anything new, and the PIN brings the conversation back. The first frames shown after the
// return are saved (return-frame-*.png): the browser shows the old frame again for an instant, which a
// page cannot prevent. Peer B is an ordinary headless page.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const root = path.resolve(process.env.SHARED_WEB_BUILD_DIR || fileURLToPath(new URL('../build/web/', import.meta.url)));
const output = process.env.WEB_QA_OUTPUT_DIR || await mkdtemp(path.join(tmpdir(), 'intragram-hidden-tab-'));
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
let browserA, browserB, chrome, profile;
const errors = [], failedRequests = [], requests = [];
const log = msg => console.log('hidden tab: ' + msg);
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const dump = async (page, name) => {
  await writeFile(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
  await page.screenshot({ path: path.join(output, name + '.png') });
};
const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const button = (page, name) => page.getByRole('button', { name: new RegExp(`^${esc(name)}(?: ${esc(name)})?$`) });
const fill = async (page, field, value) => { await field.focus(); await page.waitForTimeout(150); await page.keyboard.press('ControlOrMeta+A'); await page.keyboard.insertText(value); await page.waitForTimeout(100); };
const readCode = async page => { await button(page, 'Copy code').click(); const v = await page.evaluate(() => navigator.clipboard.readText()); assert.ok(v.startsWith('IGW1.')); return v; };
const message = (page, text) => page.getByLabel(text, { exact: false });
const composer = page => page.getByRole('textbox', { name: 'Message', exact: true });
const send = async (page, text) => { await page.bringToFront(); await fill(page, composer(page), text); await page.keyboard.press('Enter'); };
const visibility = page => page.evaluate(() => document.visibilityState);
async function start(page, name) {
  page.setDefaultTimeout(20000);
  page.on('pageerror', e => errors.push(`${name}: ${e.message}`));
  page.on('console', m => { if (m.type() === 'error') errors.push(`${name}: ${m.text()}`); });
  page.on('request', r => requests.push(r.url()));
  page.on('response', r => { if (r.status() >= 400) failedRequests.push(r.url()); });
  await page.goto(origin + '/?lang=en');
  await page.locator('flt-semantics-placeholder').waitFor();
  await page.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await page.getByRole('heading', { name: /^Intragram/ }).waitFor();
  await page.locator('#app-loading').waitFor({ state: 'detached' });
  return page;
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
// A blank tab of the same window takes the front; page A is then hidden like any background tab.
async function hide(a, cover) {
  await cover.bringToFront();
  await a.waitForFunction(() => document.visibilityState === 'hidden', null, { timeout: 15000 });
}
async function show(a) {
  await a.bringToFront();
  await a.waitForFunction(() => document.visibilityState === 'visible', null, { timeout: 15000 });
}

const pin = 'hidden789';
const secret = 'Visible secret 5512 숨긴 탭';
try {
  profile = await mkdtemp(path.join(tmpdir(), 'intragram-hidden-profile-'));
  chrome = spawn(process.env.CHROME_PATH, [`--user-data-dir=${profile}`, '--remote-debugging-port=0', '--no-first-run',
    '--no-default-browser-check', '--window-size=1280,900', '--lang=en-US', 'about:blank'], { stdio: ['ignore', 'ignore', 'pipe'] });
  const endpoint = await new Promise((resolve, reject) => {
    let text = '';
    const timer = setTimeout(() => reject(new Error('no DevTools endpoint: ' + text.slice(0, 300))), 20000);
    chrome.stderr.on('data', chunk => { text += chunk; const found = text.match(/DevTools listening on (ws:\/\/\S+)/); if (found) { clearTimeout(timer); resolve(found[1]); } });
  });
  browserA = await chromium.connectOverCDP(endpoint, { noDefaults: true });
  const contextA = browserA.contexts()[0];
  await contextA.grantPermissions(['clipboard-read', 'clipboard-write'], { origin });
  browserB = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH });
  const contextB = await browserB.newContext({ viewport: { width: 1280, height: 860 }, locale: 'en-US', permissions: ['clipboard-read', 'clipboard-write'] });
  const a = await start(contextA.pages()[0] ?? await contextA.newPage(), 'A');
  const b = await start(await contextB.newPage(), 'B');
  // Setup only: the clipboard needs a focused document, and the window may not be the active one.
  const cdp = await contextA.newCDPSession(a);
  await cdp.send('Emulation.setFocusEmulationEnabled', { enabled: true });
  await link(a, b);
  for (const p of [a, b]) await p.getByRole('heading', { name: /encrypted · code not checked/ }).waitFor();

  // Vault with a PIN and the shortest background auto-lock (1 minute), through the shared Settings UI.
  await a.bringToFront();
  await button(a, 'More').first().click();
  await a.getByRole('menuitem', { name: 'Settings', exact: true }).click();
  await a.getByRole('switch', { name: /^Keep chats on this device/ }).click();
  await a.getByRole('button', { name: /^PIN-protect the saved file/ }).click();
  await fill(a, a.getByLabel('PIN', { exact: true }), pin);
  await fill(a, a.getByLabel('Confirm PIN', { exact: true }), pin);
  await button(a, 'Save').click();
  await a.getByText('Background auto-lock', { exact: false }).first().waitFor();
  await a.getByRole('button', { name: /After 5 min/ }).click();
  await a.getByRole('menuitem', { name: 'After 1 min' }).or(a.getByRole('option', { name: 'After 1 min' })).or(a.getByRole('button', { name: 'After 1 min' })).first().click();
  await a.getByRole('button', { name: /After 1 min/ }).waitFor();
  await dump(a, 'settings-auto-lock');
  await button(a, 'Back').click();
  await composer(a).waitFor();
  await send(b, secret);
  await a.bringToFront();
  await message(a, secret).first().waitFor();
  await a.waitForTimeout(2500); // the vault saves about a second after a change
  await dump(a, 'before-hide');
  log('vault with a PIN, auto-lock after 1 minute, a message on screen');

  // From here page A has the browser's real focus and visibility.
  await cdp.send('Emulation.setFocusEmulationEnabled', { enabled: false });
  const cover = await contextA.newPage();
  await cover.goto('about:blank');

  // 1. A short absence does not lock.
  await show(a);
  await hide(a, cover);
  assert.equal(await visibility(a), 'hidden', 'the tab is really hidden (document.visibilityState)');
  await sleep(4000);
  await show(a);
  await a.waitForTimeout(800);
  assert.equal(await a.getByText('Locked vault', { exact: true }).count(), 0, 'four seconds in the background must not lock');
  await message(a, secret).first().waitFor();
  log('hidden for 4 s (document.visibilityState = hidden), back: still unlocked, message still shown');

  // 2. A minute in the background locks before anything is shown again.
  const paintsBefore = await a.evaluate(() => new Promise(resolve => { let n = 0; const end = performance.now() + 500; (function f() { n++; performance.now() < end ? requestAnimationFrame(f) : resolve(n); })(); }));
  await hide(a, cover);
  const paintsHidden = await a.evaluate(() => new Promise(resolve => { let n = 0; requestAnimationFrame(() => n++); setTimeout(() => resolve(n), 3000); }));
  assert.ok(paintsBefore > 5 && paintsHidden === 0, `a hidden tab gets no animation frame (visible ${paintsBefore} in 0.5 s, hidden ${paintsHidden} in 3 s)`);
  log(`a hidden tab paints nothing (0 animation frames in 3 s; ${paintsBefore} in 0.5 s while visible): a privacy blur cannot be drawn there`);
  await sleep(64000);
  const frames = [];
  cdp.on('Page.screencastFrame', frame => { frames.push({ data: frame.data, at: frame.metadata.timestamp }); cdp.send('Page.screencastFrameAck', { sessionId: frame.sessionId }).catch(() => {}); });
  await cdp.send('Page.startScreencast', { format: 'png', everyNthFrame: 1 });
  await show(a);
  await a.getByText('Locked vault', { exact: true }).waitFor({ timeout: 15000 });
  await a.waitForTimeout(700);
  await cdp.send('Page.stopScreencast');
  for (const [i, frame] of frames.slice(0, 4).entries()) await writeFile(path.join(output, `return-frame-${i}.png`), Buffer.from(frame.data, 'base64'));
  assert.ok(!(await a.locator('body').ariaSnapshot()).includes('5512'), 'no message text on the locked page');
  await dump(a, 'locked-after-return');
  // The browser first shows the tab's last painted frame again (the page could not repaint while hidden);
  // the first new frame must be the lock screen and must follow at once.
  const fresh = frames.find(frame => frame.data !== frames[0].data);
  assert.ok(fresh, 'a new frame was painted after the return');
  const staleMs = Math.round((fresh.at - frames[0].at) * 1000);
  assert.ok(staleMs < 1000, `the old frame stayed ${staleMs} ms before the lock screen`);
  log(`hidden for 67 s: the page came back locked (PIN gate), no message text; the browser showed the old frame for ${staleMs} ms before the first new frame (${frames.indexOf(fresh)} old, ${frames.length} in all)`);

  // 3. The PIN brings the saved conversation back.
  await cover.close();
  await a.bringToFront();
  await cdp.send('Emulation.setFocusEmulationEnabled', { enabled: true });
  await fill(a, a.getByLabel('PIN', { exact: true }), 'wrong789');
  await button(a, 'Unlock').click();
  await a.getByText('Wrong PIN', { exact: true }).waitFor();
  await fill(a, a.getByLabel('PIN', { exact: true }), pin);
  await button(a, 'Unlock').click();
  await a.getByRole('heading', { name: /^Intragram/ }).waitFor();
  await button(a, 'Search messages').click();
  await fill(a, a.locator('[data-semantics-role="text-field"][aria-label="Search messages"]'), 'Visible secret 5512');
  await a.getByRole('button', { name: /Visible secret 5512/ }).waitFor();
  await dump(a, 'unlocked-restored');
  log('wrong PIN refused, right PIN unlocked, the saved message is found again');

  const external = requests.filter(url => !url.startsWith(origin) && !url.startsWith('blob:') && !url.startsWith('data:') && url !== 'about:blank');
  assert.deepEqual(errors, []);
  assert.deepEqual(failedRequests, []);
  assert.deepEqual(external, []);
  log('no runtime errors, no failed or external requests');
  console.log('PASS');
} catch (error) {
  for (const [i, browser] of [browserA, browserB].entries()) {
    for (const context of browser?.contexts() ?? []) for (const [j, page] of context.pages().entries()) await dump(page, `error-${i}-${j}`).catch(() => {});
  }
  throw error;
} finally {
  await browserA?.close().catch(() => {});
  await browserB?.close();
  if (chrome && chrome.exitCode === null) { chrome.kill('SIGTERM'); await sleep(800); }
  if (profile) await rm(profile, { recursive: true, force: true }).catch(() => {});
  server.close();
}
