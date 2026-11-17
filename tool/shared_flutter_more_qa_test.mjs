// Shared Flutter web: keyboard send/newline/Tab, live rename, multi-file Accept all, verified
// auto-accept, block/unblock across fresh codes, QR image import, hidden-tab read hold and vault
// PIN change/remove. Real UI in isolated Chromium contexts; no app state is changed by QA code.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const root = path.resolve(process.env.SHARED_WEB_BUILD_DIR || fileURLToPath(new URL('../build/web/', import.meta.url)));
const output = process.env.WEB_QA_OUTPUT_DIR || await mkdtemp(path.join(tmpdir(), 'intragram-more-qa-'));
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
let browser;
const errors = [], failedRequests = [], requests = [], pages = [];
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
async function open(name) {
  // Retina-like scale: a screenshot of the QR dialog keeps several pixels per module.
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 2, locale: 'en-US', permissions: ['microphone', 'clipboard-read', 'clipboard-write'] });
  const page = await context.newPage();
  pages.push(page);
  page.setDefaultTimeout(20000);
  // 대화가 있는 새로고침은 앱이 브라우저 확인을 띄움: 그 확인만 수락 (나머지 대화상자는 기본처럼 닫음)
  page.on('dialog', d => d.type() === 'beforeunload' ? d.accept() : d.dismiss());
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
async function invite(host) {
  await host.bringToFront();
  await button(host, 'Encrypted app–web connection').first().click();
  await button(host, 'Create invitation code').click();
  await host.getByRole('textbox', { name: 'Your connection code', exact: true }).waitFor();
  return readCode(host);
}
async function answer(guest, offer) {
  await guest.bringToFront();
  await button(guest, 'Encrypted app–web connection').first().click();
  await button(guest, 'Join with a code').click();
  await fill(guest, guest.getByRole('textbox', { name: 'Their invitation code', exact: true }), offer);
  await button(guest, 'Create response code').click();
  await guest.getByRole('textbox', { name: 'Your connection code', exact: true }).waitFor();
  const code = await readCode(guest);
  await button(guest, 'Open conversation').click();
  return code;
}
async function connect(host, guest, response) {
  await host.bringToFront();
  await fill(host, host.getByRole('textbox', { name: 'Their response code', exact: true }), response);
  await button(host, 'Connect').click();
}
async function chatMenu(page, item) {
  await page.bringToFront();
  await button(page, 'More').last().click();
  await page.getByRole('menuitem', { name: item, exact: true }).click();
}
async function verify(a, b) {
  for (const p of [a, b]) {
    await p.bringToFront();
    await button(p, 'Check security code').click();
    await button(p, 'They match').click();
  }
  for (const p of [a, b]) await button(p, 'Security code verified').waitFor();
}
async function saved(page, name) {
  const download = page.waitForEvent('download');
  await page.getByRole('group', { name: new RegExp(esc(name)) }).getByRole('button', { name: 'Save to device', exact: true }).click();
  return readFile(await (await download).path());
}

try {
  browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH, args: ['--use-fake-device-for-media-stream'] });
  const a = await open('A'), b = await open('B');

  // QR image import: the host's own QR dialog is screenshotted and read back by the guest.
  const offer = await invite(a);
  await button(a, 'Show QR code').click();
  const qrDialog = a.getByRole('alertdialog').last();
  await a.waitForTimeout(400);
  const qrPng = path.join(output, 'invitation-qr.png');
  await qrDialog.screenshot({ path: qrPng });
  await button(a, 'Close').last().click();
  await b.bringToFront();
  await button(b, 'Encrypted app–web connection').first().click();
  await button(b, 'Join with a code').click();
  // An image without a QR code says so instead of silently doing nothing.
  const blank = path.join(output, 'no-qr.png');
  await b.screenshot({ path: blank, clip: { x: 0, y: 0, width: 240, height: 120 } });
  const [blankChooser] = await Promise.all([b.waitForEvent('filechooser'), button(b, 'Read a QR image').click()]);
  await blankChooser.setFiles(blank);
  await b.getByText('No QR code could be read from that image.').waitFor();
  const [qrChooser] = await Promise.all([b.waitForEvent('filechooser'), button(b, 'Read a QR image').click()]);
  await qrChooser.setFiles(qrPng);
  // The decoded invitation fills the field; creating a response proves it was the exact offer.
  await b.waitForTimeout(1500);
  await button(b, 'Create response code').click();
  await b.getByRole('textbox', { name: 'Your connection code', exact: true }).waitFor();
  const response = await readCode(b);
  await button(b, 'Open conversation').click();
  await connect(a, b, response);
  for (const p of [a, b]) await p.getByRole('heading', { name: /encrypted · code not checked/ }).waitFor();
  console.log('more QA: QR image of the invitation read back by the joining browser and connected');

  // Typing indicator: an unsent draft shows "typing…" on the peer; sending it clears the indicator.
  await a.bringToFront();
  await fill(a, composer(a), 'Draft that is not sent yet');
  await b.bringToFront();
  await b.getByRole('heading', { name: /typing…/ }).waitFor();
  await a.bringToFront();
  await button(a, 'Send').last().click();
  await b.bringToFront();
  await message(b, 'Draft that is not sent yet').waitFor();
  await b.getByRole('heading', { name: /typing…/ }).waitFor({ state: 'detached' });
  console.log('more QA: typing indicator shown for an unsent draft and cleared after sending');

  // Page shortcuts (the browser keeps Cmd/Ctrl+N/W/Tab): Cmd/Ctrl+F searches the open chat, Esc closes,
  // Cmd/Ctrl+, opens Settings.
  await a.bringToFront();
  await a.keyboard.press('ControlOrMeta+f');
  await a.getByRole('textbox', { name: 'Search in chat', exact: true }).waitFor();
  await a.keyboard.press('Escape');
  await a.getByRole('textbox', { name: 'Search in chat', exact: true }).waitFor({ state: 'detached' });
  await a.keyboard.press('ControlOrMeta+Comma');
  await a.getByRole('heading', { name: 'Settings', exact: true }).waitFor();
  await a.keyboard.press('Escape');
  await a.getByRole('heading', { name: 'Settings', exact: true }).waitFor({ state: 'detached' });
  console.log('more QA: Cmd/Ctrl+F opens search in the chat, Esc closes it, Cmd/Ctrl+, opens Settings and Esc returns');

  // Keyboard: Shift+Enter keeps one multi-line message, Enter sends; Shift+Tab leaves the field.
  await b.bringToFront();
  await fill(b, composer(b), 'Line one');
  await b.keyboard.press('Shift+Enter');
  await b.waitForTimeout(150);
  await b.keyboard.insertText('Line two');
  await b.waitForTimeout(150);
  await b.keyboard.press('Enter');
  await a.bringToFront();
  await message(a, 'Line one\nLine two').waitFor();
  assert.equal(await composer(b).inputValue(), '');
  await b.bringToFront();
  await composer(b).focus();
  await b.waitForTimeout(200);
  await b.keyboard.press('Shift+Tab');
  await b.waitForTimeout(200);
  const focused = await b.evaluate(() => document.activeElement?.getAttribute('aria-label') || document.activeElement?.textContent || '');
  assert.ok(/record|file|clipboard/i.test(focused), 'Shift+Tab moves to a composer action: ' + focused);
  console.log('more QA: Enter sends, Shift+Enter newline in one message, Shift+Tab reaches composer actions');

  // Live rename reaches the connected peer.
  await a.bringToFront();
  // The identity card merges its semantics; its tap opens the rename dialog.
  await a.getByRole('group', { name: /^Web device / }).first().click();
  await fill(a, a.getByRole('textbox').last(), 'renamed-alpha-01');
  await button(a, 'Rename').click();
  await b.bringToFront();
  await b.getByRole('heading', { name: /^renamed-alpha-01/ }).waitFor();
  console.log('more QA: rename propagates to the live WebRTC peer');

  // Several files offered together: Accept all.
  const one = Buffer.from('first file\n'), two = Buffer.from('second file 두번째\n');
  const [multi] = await Promise.all([b.waitForEvent('filechooser'), button(b, 'Send a file').last().click()]);
  await multi.setFiles([{ name: 'multi-1.txt', mimeType: 'text/plain', buffer: one }, { name: 'multi-2.txt', mimeType: 'text/plain', buffer: two }]);
  // Both offers are visible at once (one batch, as in native v7): Accept all takes them together.
  await a.bringToFront();
  await a.getByRole('group', { name: /multi-2\.txt/ }).waitFor();
  await a.getByRole('group', { name: /multi-1\.txt/ }).getByRole('button', { name: 'Accept all (2)', exact: true }).click();
  assert.deepEqual(await saved(a, 'multi-1.txt'), one);
  assert.deepEqual(await saved(a, 'multi-2.txt'), two);
  console.log('more QA: two files picked together arrive as one batch; Accept all saves both byte-exact');

  // Auto-accept is offered only after both sides verify the code.
  await verify(a, b);
  await chatMenu(a, 'Auto-accept files');
  const auto = Buffer.from('auto accepted after verification\n');
  const [autoChooser] = await Promise.all([b.waitForEvent('filechooser'), button(b, 'Send a file').last().click()]);
  await autoChooser.setFiles({ name: 'auto.txt', mimeType: 'text/plain', buffer: auto });
  await a.bringToFront();
  await a.getByRole('group', { name: /auto\.txt/ }).getByRole('button', { name: 'Save to device', exact: true }).waitFor();
  assert.equal(await a.getByRole('group', { name: /auto\.txt/ }).getByRole('button', { name: 'Accept', exact: true }).count(), 0);
  assert.deepEqual(await saved(a, 'auto.txt'), auto);
  console.log('more QA: verified 1:1 auto-accept received without a tap');

  // Hidden tab: no read receipt until the receiver is in front again.
  const focus = await b.context().newCDPSession(b);
  await focus.send('Emulation.setFocusEmulationEnabled', { enabled: false });
  const cover = await b.context().newPage();
  await cover.bringToFront();
  await b.waitForFunction(() => !document.hasFocus());
  await send(a, 'Sent while the other tab is in the background');
  await a.waitForTimeout(2500);
  assert.doesNotMatch(await message(a, 'Sent while the other tab is in the background').getAttribute('aria-label'), /\bread\b/);
  await b.bringToFront(); await cover.close();
  await focus.send('Emulation.setFocusEmulationEnabled', { enabled: true });
  await focus.detach();
  await a.bringToFront();
  for (let i = 0; i < 50 && !/\bread\b/.test(await message(a, 'Sent while the other tab is in the background').getAttribute('aria-label')); i++) await a.waitForTimeout(200);
  assert.match(await message(a, 'Sent while the other tab is in the background').getAttribute('aria-label'), /\bread\b/);
  console.log('more QA: hidden receiver holds the read receipt until it is in front');

  // Block, refused reconnect with fresh codes, unblock, reconnect.
  await chatMenu(a, 'Block this device');
  await a.getByRole('alertdialog').getByRole('button', { name: 'Block this device', exact: true }).click();
  await a.getByText('You blocked this device').first().waitFor();
  await dump(a, 'blocked');
  const offer2 = await invite(a);
  const response2 = await answer(b, offer2);
  await connect(a, b, response2);
  await a.waitForTimeout(4000);
  await dump(a, 'blocked-reconnect');
  assert.equal(await a.getByRole('heading', { name: /encrypted · code not checked/ }).count(), 0, 'blocked identity must not open a chat');
  await button(a, 'Unblock').first().click();
  const offer3 = await invite(a);
  const response3 = await answer(b, offer3);
  await connect(a, b, response3);
  for (const p of [a, b]) await p.getByRole('heading', { name: /encrypted · code not checked/ }).waitFor();
  await send(b, 'Back after unblock');
  await message(a, 'Back after unblock').waitFor();
  console.log('more QA: block refuses the same identity on fresh codes; unblock allows reconnect');

  // Vault PIN change and removal through the shared Settings UI.
  await b.bringToFront();
  await button(b, 'More').first().click();
  await b.getByRole('menuitem', { name: 'Settings', exact: true }).click();
  await b.getByRole('switch', { name: /^Keep chats on this device/ }).click();
  await b.getByRole('button', { name: /^PIN-protect the saved file/ }).click();
  await fill(b, b.getByLabel('PIN', { exact: true }), 'firstpin1');
  await fill(b, b.getByLabel('Confirm PIN', { exact: true }), 'firstpin1');
  await button(b, 'Save').click();
  await b.getByRole('button', { name: /^PIN-protect the saved file/ }).click();
  await b.getByText('Change vault PIN', { exact: true }).waitFor();
  await fill(b, b.getByLabel('PIN', { exact: true }), 'secondpin2');
  await fill(b, b.getByLabel('Confirm PIN', { exact: true }), 'secondpin2');
  await button(b, 'Save').click();
  await b.waitForTimeout(1500);
  await b.reload();
  await b.locator('flt-semantics-placeholder').waitFor();
  await b.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await b.getByText('Locked vault', { exact: true }).waitFor();
  await fill(b, b.getByLabel('PIN', { exact: true }), 'firstpin1');
  await button(b, 'Unlock').click();
  await b.getByText('Wrong PIN', { exact: true }).waitFor();
  await fill(b, b.getByLabel('PIN', { exact: true }), 'secondpin2');
  await button(b, 'Unlock').click();
  await b.getByRole('heading', { name: /^Intragram/ }).waitFor();
  await button(b, 'More').first().click();
  await b.getByRole('menuitem', { name: 'Settings', exact: true }).click();
  await b.getByRole('button', { name: /^PIN-protect the saved file/ }).click();
  await button(b, 'Remove PIN').click();
  await b.getByRole('button', { name: /^PIN-protect the saved file\s+Off — saved chats are plain JSON in this browser's site storage/ }).waitFor();
  await b.waitForTimeout(1500);
  await b.reload();
  await b.locator('flt-semantics-placeholder').waitFor();
  await b.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await b.getByRole('heading', { name: /^Intragram/ }).waitFor();
  assert.equal(await b.getByText('Locked vault', { exact: true }).count(), 0);
  console.log('more QA: vault PIN set, changed (old PIN rejected after reload), removed (no lock after reload)');

  // Files a closed tab received into OPFS are removed when the app starts again in that profile.
  const opfsFiles = page => page.evaluate(async () => {
    let tmp; try { tmp = await (await navigator.storage.getDirectory()).getDirectoryHandle('intragram-recv-tmp'); } catch { return []; }
    const files = [];
    for await (const [name, handle] of tmp.entries()) {
      if (handle.kind !== 'directory') { files.push(name); continue; }
      for await (const inner of handle.keys()) files.push(name + '/' + inner);
    }
    return files;
  });
  assert.ok((await opfsFiles(a)).length >= 3, 'received files were streamed into OPFS');
  const profile = a.context();
  await a.close();
  const reopened = await profile.newPage();
  reopened.on('pageerror', e => errors.push(`A2: ${e.message}`));
  reopened.on('console', m => { if (m.type() === 'error') errors.push(`A2: ${m.text()}`); });
  reopened.on('request', r => requests.push(r.url()));
  await reopened.goto(origin + '/?lang=en');
  await reopened.locator('flt-semantics-placeholder').waitFor();
  await reopened.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await reopened.getByRole('heading', { name: /^Intragram/ }).waitFor();
  for (let i = 0; i < 50 && (await opfsFiles(reopened)).length; i++) await reopened.waitForTimeout(100);
  assert.deepEqual(await opfsFiles(reopened), []);
  console.log('more QA: received files a closed tab left in OPFS are removed when the app starts again');

  assert.deepEqual(errors, []);
  assert.deepEqual(failedRequests, []);
  assert.ok(requests.every(r => r.startsWith(origin + '/') || r.startsWith('blob:') || r.startsWith('data:')));
  console.log('PASS: shared Flutter more QA. Artifacts: ' + output);
} catch (error) {
  for (let i = 0; i < pages.length; i++) await dump(pages[i], 'failure-' + i).catch(() => {});
  console.error('artifacts: ' + output + '\nerrors: ' + JSON.stringify(errors) + '\nfailed: ' + JSON.stringify(failedRequests));
  throw error;
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
}
