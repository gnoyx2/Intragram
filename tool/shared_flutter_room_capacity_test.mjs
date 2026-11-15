// Shared Flutter web room at its limit: one Flutter host, 31 members over real WebRTC links in
// headless Chromium (2 Flutter members, 29 auxiliary HTML clients to keep memory sane). Checked: the
// host shows 32 people, a host message reaches every member, a member message is relayed to the
// host and the other members, the 33rd invitation is refused with the limit message, and a seat
// freed by a leaving member can be invited again.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const flutterRoot = path.resolve(process.env.SHARED_WEB_BUILD_DIR || fileURLToPath(new URL('../build/web/', import.meta.url)));
const liteRoot = fileURLToPath(new URL('../docs/', import.meta.url));
const output = process.env.WEB_QA_OUTPUT_DIR || await mkdtemp(path.join(tmpdir(), 'intragram-capacity-'));
await mkdir(output, { recursive: true });
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.jpg': 'image/jpeg', '.ttf': 'font/ttf', '.woff2': 'font/woff2' };
const serve = root => new Promise(resolve => {
  const server = createServer(async (req, res) => {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    const file = path.resolve(root, '.' + pathname + (pathname.endsWith('/') ? 'index.html' : ''));
    if (!file.startsWith(root + path.sep) && file !== root) { res.writeHead(403).end(); return; }
    try { const bytes = await readFile(file); res.writeHead(200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream' }); res.end(bytes); }
    catch { res.writeHead(404).end(); }
  }).listen(0, '127.0.0.1', () => resolve(server));
});
const flutterServer = await serve(flutterRoot), liteServer = await serve(path.resolve(liteRoot));
const origin = `http://127.0.0.1:${flutterServer.address().port}`;
const liteUrl = `http://127.0.0.1:${liteServer.address().port}/web/lite.html?lang=en`;
const members = Number(process.env.CAPACITY_MEMBERS || 31), flutterMembers = 2;
let browser;
const errors = [], failedRequests = [], requests = [];
const log = msg => console.log('capacity: ' + msg);
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
function watch(page, name) {
  page.setDefaultTimeout(30000);
  page.on('pageerror', e => errors.push(`${name}: ${e.message}`));
  page.on('console', m => { if (m.type() === 'error') errors.push(`${name}: ${m.text()}`); });
  page.on('request', r => requests.push(r.url()));
  page.on('response', r => { if (r.status() >= 400) failedRequests.push(r.url()); });
  return page;
}
async function openFlutter(name) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, locale: 'en-US', permissions: ['clipboard-read', 'clipboard-write'] });
  const page = watch(await context.newPage(), name);
  await page.goto(origin + '/?lang=en');
  await page.locator('flt-semantics-placeholder').waitFor();
  await page.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await page.getByRole('heading', { name: /^Intragram/ }).waitFor();
  await page.locator('#app-loading').waitFor({ state: 'detached' });
  return page;
}
async function openLite(name) {
  const context = await browser.newContext({ viewport: { width: 800, height: 600 }, locale: 'en-US' });
  const page = watch(await context.newPage(), name);
  await page.goto(liteUrl);
  await page.locator('#mode-join').waitFor();
  return page;
}
// The host opens an invitation: the first from Home, later ones from Add people in the open room.
async function invite(host, add) {
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
}
async function connect(host, response) {
  await host.bringToFront();
  await fill(host, host.getByRole('textbox', { name: 'Their response code', exact: true }), response);
  await button(host, 'Connect').click();
  await host.getByRole('textbox', { name: 'Their response code', exact: true }).waitFor({ state: 'detached' });
}
async function joinFlutter(host, guest, add) {
  await invite(host, add);
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
  await connect(host, response);
}
async function joinLite(host, guest) {
  await invite(host, true);
  await host.getByRole('textbox', { name: 'Your connection code', exact: true }).waitFor();
  const offer = await readCode(host);
  await guest.locator('#mode-join').click();
  await guest.locator('#invite-code').fill(offer);
  await guest.locator('#accept-offer').click();
  await guest.waitForFunction(() => document.querySelector('#local-code').value.startsWith('IGW1.'));
  const response = await guest.locator('#local-code').inputValue();
  await connect(host, response);
  await guest.locator('#chat:visible').waitFor();
}
const people = async (page, n) => page.waitForFunction(count => [...document.querySelectorAll('[aria-label],flt-semantics')].some(e => (e.getAttribute('aria-label') || e.textContent || '').includes(`${count} people`)), n, { timeout: 30000 });

try {
  browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH });
  const host = await openFlutter('host');
  const flutter = [], lite = [];
  const started = Date.now();
  for (let i = 0; i < members; i++) {
    if (i < flutterMembers) {
      const page = await openFlutter(`F${i + 1}`);
      await joinFlutter(host, page, i > 0);
      flutter.push(page);
    } else {
      const page = await openLite(`L${i + 1}`);
      await joinLite(host, page);
      lite.push(page);
    }
    if ((i + 1) % 5 === 0 || i + 1 === members) log(`${i + 1} members connected (${Math.round((Date.now() - started) / 1000)} s)`);
  }
  await people(host, members + 1);
  await dump(host, 'host-full-room');
  log(`the host shows ${members + 1} people`);

  // Host -> every member.
  const fromHost = `Broadcast to all ${members + 1} 방 전체`;
  await send(host, fromHost);
  for (const page of flutter) await message(page, fromHost).first().waitFor();
  for (const page of lite) await page.getByText(fromHost, { exact: true }).waitFor();
  log(`a host message reached all ${members} members`);

  // The last member -> host and the other members (relayed by the host).
  const last = lite.at(-1), fromMember = 'From the last member 마지막 멤버';
  await last.locator('#message-input').fill(fromMember);
  await last.locator('#send').click();
  await message(host, fromMember).first().waitFor();
  for (const page of flutter) await message(page, fromMember).first().waitFor();
  for (const page of lite.slice(0, -1)) await page.getByText(fromMember, { exact: true }).waitFor();
  log('a message from the last member was relayed to the host and every other member');

  if (members === 31) {
    // The 33rd seat does not exist.
    await invite(host, true);
    await host.getByText('This room has reached its participant limit.', { exact: false }).first().waitFor();
    await dump(host, 'host-33rd-refused');
    await host.keyboard.press('Escape');
    await host.waitForTimeout(400);
    if (await button(host, 'Add').count()) { await host.keyboard.press('Escape'); await host.waitForTimeout(400); }
    log('the 33rd invitation is refused: "This room has reached its participant limit."');

    // A member leaves; its seat can be invited again.
    const leaving = flutter[1];
    await leaving.bringToFront();
    await button(leaving, 'More').last().click();
    await leaving.getByRole('menuitem', { name: 'End conversation', exact: true }).click();
    await leaving.getByRole('alertdialog').getByRole('button', { name: 'End', exact: true }).click();
    await people(host, members);
    await invite(host, true);
    await host.getByRole('textbox', { name: 'Your connection code', exact: true }).waitFor();
    assert.ok((await readCode(host)).startsWith('IGW1.'));
    log(`after one member left the host shows ${members} people and can invite again`);
  }

  const external = requests.filter(url => !url.startsWith(origin) && !url.startsWith(new URL(liteUrl).origin) && !url.startsWith('blob:') && !url.startsWith('data:'));
  assert.deepEqual(errors, []);
  assert.deepEqual(failedRequests, []);
  assert.deepEqual(external, []);
  log('no runtime errors, no failed or external requests');
  console.log('PASS');
} catch (error) {
  const pages = browser?.contexts().flatMap(context => context.pages()) ?? [];
  if (pages[0]) await dump(pages[0], 'error-host').catch(() => {});
  if (pages.length > 1) await dump(pages.at(-1), 'error-last').catch(() => {});
  throw error;
} finally {
  await browser?.close();
  flutterServer.close();
  liteServer.close();
}
