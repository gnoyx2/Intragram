// Shared Flutter web gap QA: flows that only had unit tests before, driven through the real UI in
// isolated Chromium contexts. A reply keeps no copy of a burned original, global search follows
// new and deleted messages while it is open, an organization credential is withdrawn, a second
// device witnesses an audit bundle (wrong witness and tampered bundle are refused), a dropped
// folder (with a nested folder) is offered file by file, and the Saved chats screen lists and
// deletes a saved conversation.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const root = path.resolve(process.env.SHARED_WEB_BUILD_DIR || fileURLToPath(new URL('../build/web/', import.meta.url)));
const output = process.env.WEB_QA_OUTPUT_DIR || await mkdtemp(path.join(tmpdir(), 'intragram-gap-qa-'));
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
const errors = [], failedRequests = [], requests = [];
const log = msg => console.log('gap QA: ' + msg);
const sha = b => createHash('sha256').update(b).digest('hex');
const dump = async (page, name) => {
  await writeFile(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
  await page.screenshot({ path: path.join(output, name + '.png') });
};
const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const button = (page, name) => page.getByRole('button', { name: new RegExp(`^${esc(name)}(?: ${esc(name)})?$`) });
const fill = async (page, field, value) => { await field.focus(); await page.waitForTimeout(150); await page.keyboard.press('ControlOrMeta+A'); await page.keyboard.insertText(value); await page.waitForTimeout(100); };
const clip = page => page.evaluate(() => navigator.clipboard.readText());
const readCode = async page => { await button(page, 'Copy code').click(); const v = await clip(page); assert.ok(v.startsWith('IGW1.')); return v; };
const message = (page, text) => page.getByLabel(text, { exact: false });
const composer = page => page.getByRole('textbox', { name: 'Message', exact: true });
const send = async (page, text) => { await page.bringToFront(); await fill(page, composer(page), text); await page.keyboard.press('Enter'); };
const tile = (page, name) => page.getByRole('group', { name: new RegExp(esc(name)) });
const noLabelWith = (page, text, timeout) => page.waitForFunction(
  t => ![...document.querySelectorAll('[aria-label]')].some(e => e.getAttribute('aria-label').includes(t)), text, { timeout });
// 메시지 동작 메뉴: 스크린 리더와 같은 경로. Flutter가 포인터를 받는 flutter-view 위 좌표로 우클릭함
const messageAction = async (page, locator, item) => {
  const box = await locator.first().boundingBox();
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2, { button: 'right' });
  await page.getByRole('menuitem', { name: item }).or(page.getByRole('button', { name: item })).first().click();
};
async function open(name) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, locale: 'en-US', permissions: ['clipboard-read', 'clipboard-write'] });
  const page = await context.newPage();
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
async function verify(a, b) {
  for (const p of [a, b]) {
    await p.bringToFront();
    await button(p, 'Check security code').click();
    await button(p, 'They match').click();
  }
  for (const p of [a, b]) await button(p, 'Security code verified').waitFor();
}
async function attach(page, file) {
  await page.bringToFront();
  const [chooser] = await Promise.all([page.waitForEvent('filechooser'), button(page, 'Send a file').last().click()]);
  await chooser.setFiles(file);
}
async function saved(page, name) {
  const download = page.waitForEvent('download');
  await tile(page, name).getByRole('button', { name: 'Save to device', exact: true }).click();
  return readFile(await (await download).path());
}
async function openAudit(page) {
  await page.bringToFront();
  await button(page, 'More').last().click();
  await page.getByRole('menuitem', { name: 'Audit & Merkle Proofs', exact: true }).click();
}
const pasteField = page => page.getByLabel('Paste audit bundle or witness receipt JSON', { exact: true });
const witnessField = page => page.getByLabel('Independently confirmed witness peer ID', { exact: true });
const result = (page, text) => page.getByText(text).first().waitFor({ timeout: 30000 });

try {
  browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH });
  const a = await open('A'), b = await open('B');
  await link(a, b);
  await verify(a, b);
  log('A and B connected with a verified security code');

  // 1. A reply written before the original burns keeps no copy of it afterwards.
  const secret = 'Burning original 9431 소각될 원문';
  const replyText = 'Reply that outlives the original';
  await a.bringToFront();
  await button(a, 'Self-destruct timer').click();
  await a.getByRole('menuitem', { name: 'Burn after 30s', exact: true }).click();
  await send(a, secret);
  await button(a, 'Self-destruct timer').click();
  await a.getByRole('menuitem', { name: 'Timer off', exact: true }).click();
  await b.bringToFront();
  await message(b, secret).first().waitFor();
  await messageAction(b, message(b, secret), 'Reply');
  await send(b, replyText);
  for (const p of [a, b]) {
    await message(p, replyText).first().waitFor();
    assert.match(await message(p, replyText).first().getAttribute('aria-label'), /Burning original 9431/, 'the reply quotes the original while it exists');
  }
  await dump(b, 'burn-quote-before');
  for (const p of [a, b]) await noLabelWith(p, '9431', 60000);
  for (const p of [a, b]) {
    const label = await message(p, replyText).first().getAttribute('aria-label');
    assert.match(label, /Message deleted/, 'the quote says the original is gone');
    assert.ok(!(await p.locator('body').ariaSnapshot()).includes('9431'), 'no burned text anywhere on the page');
  }
  await dump(b, 'burn-quote-after');
  log('30 s timer: the original burned on both sides; the reply stays and its quote reads "Message deleted"');

  // 2. Global search follows the conversation while it is open.
  const needle = 'needle-7Q42';
  await a.bringToFront();
  await button(a, 'Search messages').click();
  // An autofocused field also has Flutter's hidden editing input with the same placeholder.
  await fill(a, a.locator('[data-semantics-role="text-field"][aria-label="Search messages"]'), needle);
  await a.getByText(/No matches/).first().waitFor();
  await send(b, `${needle} arrives while the search is open`);
  await a.bringToFront();
  const hit = a.getByRole('button', { name: new RegExp(`${needle} arrives while the search is open`) });
  await hit.waitFor();
  await dump(a, 'search-live-hit');
  await b.bringToFront();
  await messageAction(b, message(b, `${needle} arrives while the search is open`), /^Delete for everyone/);
  await noLabelWith(b, needle, 20000);
  await a.bringToFront();
  await hit.waitFor({ state: 'detached' });
  await a.getByText(/No matches/).first().waitFor();
  await dump(a, 'search-live-removed');
  await button(a, 'Back').click();
  await composer(a).waitFor();
  log('global search showed a message that arrived while it was open and dropped it when the sender deleted it for everyone');

  // 3. Organization credential: presented, verified by the peer, then withdrawn.
  await a.bringToFront();
  await button(a, 'Organization credential not presented').click();
  await button(a, 'Issue and activate demo credential').click();
  await button(a, 'Stop presenting').waitFor();
  assert.match(await a.locator('body').ariaSnapshot(), /Demo Research Institute · Security Research · Researcher/, 'own credential details are readable');
  await button(a, 'Close').click();
  await b.bringToFront();
  const presented = b.getByRole('button', { name: /Demo issuer · Demo Research Institute/ });
  await presented.waitFor();
  await a.bringToFront();
  await button(a, 'Organization credential not presented').click();
  await button(a, 'Stop presenting').click();
  await button(a, 'Issue and activate demo credential').waitFor();
  await button(a, 'Close').click();
  await b.bringToFront();
  await presented.waitFor({ state: 'detached' });
  await button(b, 'Organization credential not presented').waitFor();
  await dump(b, 'org-withdrawn');
  log('demo organization credential verified by the peer, then withdrawn: the peer shows "not presented" again');

  // 4. Audit: B witnesses A's Merkle batch; a wrong witness ID and a tampered bundle are refused.
  const payload = Buffer.from('evidence file 증적 파일\n');
  await attach(a, { name: 'evidence.txt', mimeType: 'text/plain', buffer: payload });
  await b.bringToFront();
  await tile(b, 'evidence.txt').getByRole('button', { name: 'Accept', exact: true }).click();
  assert.deepEqual(await saved(b, 'evidence.txt'), payload);
  await openAudit(a);
  await button(a, 'Commit Merkle batch').click();
  // The batch row is one node: "Merkle batch 1 · N receipts <root> <anchor state>" (the root is readable too).
  const batchRow = state => a.getByRole('group', { name: new RegExp(`^Merkle batch 1 · \\d+ receipts [A-Za-z0-9+/=]{44} ${state}$`) });
  await batchRow('External anchor bundle ready · no witness verified').waitFor();
  await button(a, 'Copy JSON audit bundle').click();
  const bundle = await clip(a);
  assert.ok(bundle.includes('intragram-audit-anchor-bundle/v1'));
  const parsed = JSON.parse(bundle);
  assert.ok(parsed.entries.length > 0 && !parsed.anchor, 'bundle has entries and no anchor yet');

  await openAudit(b);
  await button(b, 'Export / verify external anchor bundle').click();
  // Selectable text must be readable by assistive technology: Flutter web exposes a read-only field's
  // value nowhere, so the app names it (this line used to be an empty, nameless textbox).
  await pasteField(b).waitFor();
  const peerLine = (await b.locator('body').ariaSnapshot()).match(/This device's peer ID: ([0-9a-f]{32})/);
  assert.ok(peerLine, 'B shows its peer ID');
  const witnessId = peerLine[1];
  const tampered = structuredClone(parsed);
  const salt = Buffer.from(tampered.entries[0].salt, 'base64'); salt[0] ^= 1;
  tampered.entries[0].salt = salt.toString('base64');
  await fill(b, pasteField(b), JSON.stringify(tampered));
  await button(b, 'Verify audit bundle').click();
  await result(b, 'Verification failed');
  await button(b, 'Sign external root & copy receipt').click();
  await result(b, 'Verification failed');
  await dump(b, 'audit-tampered-refused');
  await fill(b, pasteField(b), bundle);
  await button(b, 'Verify audit bundle').click();
  await result(b, /Bundle signatures and proofs verified · external witness unconfirmed/);
  await b.evaluate(() => navigator.clipboard.writeText('not a receipt'));
  await button(b, 'Sign external root & copy receipt').click();
  await result(b, /Witness receipt signed and copied/);
  const receipt = await clip(b);
  assert.notEqual(receipt, 'not a receipt');
  JSON.parse(receipt);
  await dump(b, 'audit-witness-signed');

  await a.bringToFront();
  await button(a, 'Export / verify external anchor bundle').click();
  await fill(a, pasteField(a), receipt);
  await fill(a, witnessField(a), 'f'.repeat(32));
  await button(a, 'Verify & attach witness receipt').click();
  await result(a, 'Verification failed');
  await fill(a, witnessField(a), witnessId);
  await button(a, 'Verify & attach witness receipt').click();
  await result(a, 'External anchor verified');
  await dump(a, 'audit-anchor-attached');
  await button(a, 'Close').last().click();
  await a.waitForTimeout(300);
  await batchRow('External anchor verified').waitFor();
  assert.equal(await batchRow('External anchor bundle ready · no witness verified').count(), 0, 'the batch no longer says it has no witness');
  await button(a, 'Copy JSON audit bundle').click();
  const anchored = await clip(a);
  assert.ok(JSON.parse(anchored).anchor, 'the exported bundle now carries the witness receipt');
  await button(a, 'Export / verify external anchor bundle').click();
  await fill(a, pasteField(a), anchored);
  await fill(a, witnessField(a), witnessId);
  await button(a, 'Verify audit bundle').click();
  await result(a, 'External anchor verified');
  await button(a, 'Close').last().click();
  await a.waitForTimeout(300);
  await button(a, 'Close').first().click();
  await b.bringToFront();
  await button(b, 'Close').last().click();
  await b.waitForTimeout(300);
  await button(b, 'Close').first().click();
  log('B verified and witnessed A\'s Merkle batch; A attached the receipt only with B\'s real peer ID; a tampered bundle failed');

  // 5. Folder drop: Chromium delivers a real OS-style drag of a folder; the app walks it and
  //    offers every file inside (nested folder included).
  const folder = path.join(output, 'dropped-folder');
  await mkdir(path.join(folder, 'inner'), { recursive: true });
  const one = Buffer.from('first file in the dropped folder 첫 파일\n');
  const two = Buffer.alloc(70001); for (let i = 0; i < two.length; i++) two[i] = (i * 29 + 3) & 0xff;
  await writeFile(path.join(folder, 'drop-one.txt'), one);
  await writeFile(path.join(folder, 'inner', 'drop-two.bin'), two);
  await a.bringToFront();
  await composer(a).waitFor();
  const drag = await a.context().newCDPSession(a);
  const data = { items: [], files: [folder], dragOperationsMask: 1 };
  for (const type of ['dragEnter', 'dragOver', 'drop']) {
    await drag.send('Input.dispatchDragEvent', { type, x: 1000, y: 500, data });
    await a.waitForTimeout(250);
  }
  await drag.detach();
  await b.bringToFront();
  await tile(b, 'drop-one.txt').first().waitFor();
  await tile(b, 'drop-two.bin').first().waitFor();
  await dump(b, 'folder-drop-offered');
  await b.getByRole('button', { name: 'Accept all (2)', exact: true }).first().click();
  assert.deepEqual(await saved(b, 'drop-one.txt'), one);
  assert.equal(sha(await saved(b, 'drop-two.bin')), sha(two));
  log('a dropped folder with a nested folder was offered as two files; both saved byte-exact');

  // 6. Saved chats: with saving on, the conversation is listed in Settings and can be deleted from there.
  await a.bringToFront();
  await button(a, 'More').first().click();
  await a.getByRole('menuitem', { name: 'Settings', exact: true }).click();
  await a.getByRole('switch', { name: /^Keep chats on this device/ }).click();
  await a.getByRole('button', { name: /^Saved chats/ }).click();
  await a.getByText('Saved Chats', { exact: true }).first().waitFor();
  await button(a, 'Delete').first().waitFor();
  await dump(a, 'saved-chats-listed');
  await button(a, 'Delete').first().click();
  await a.getByText('Delete this saved chat?', { exact: true }).waitFor();
  await a.getByRole('alertdialog').getByRole('button', { name: 'Delete', exact: true }).click();
  await a.getByText(/Nothing saved yet/).first().waitFor();
  await dump(a, 'saved-chats-empty');
  log('Saved chats listed the conversation; deleting it there left "Nothing saved yet"');

  const external = requests.filter(url => !url.startsWith(origin) && !url.startsWith('blob:') && !url.startsWith('data:'));
  assert.deepEqual(errors, []);
  assert.deepEqual(failedRequests, []);
  assert.deepEqual(external, []);
  log('no runtime errors, no failed or external requests');
  console.log('PASS');
} catch (error) {
  for (const [i, context] of (browser?.contexts() ?? []).entries()) {
    for (const page of context.pages()) await dump(page, `error-${i}`).catch(() => {});
  }
  throw error;
} finally {
  await browser?.close();
  server.close();
}
