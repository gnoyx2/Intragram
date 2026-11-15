import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import { mkdir, mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const root = path.resolve(process.env.SHARED_WEB_BUILD_DIR || fileURLToPath(new URL('../build/web/', import.meta.url)));
const output = process.env.WEB_QA_OUTPUT_DIR || await mkdtemp(path.join(tmpdir(), 'intragram-extended-qa-'));
const tempFilesDir = await mkdtemp(path.join(tmpdir(), 'intragram-300mb-'));
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

async function sha256File(filePath) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(filePath)) hash.update(chunk);
  return hash.digest('base64');
}

async function generateSyntheticFile(filePath, totalBytes) {
  const hash = createHash('sha256');
  const out = createWriteStream(filePath);
  const block = Buffer.allocUnsafe(1024 * 1024);
  for (let i = 0; i < block.length; i++) block[i] = (i * 37 + 11) & 0xff;
  let written = 0;
  while (written < totalBytes) {
    const slice = written + block.length <= totalBytes ? block : block.subarray(0, totalBytes - written);
    block[0] = (written >>> 20) & 0xff;
    hash.update(slice);
    if (!out.write(slice)) await new Promise(r => out.once('drain', r));
    written += slice.length;
  }
  await new Promise((resolve, reject) => { out.end(); out.on('finish', resolve); out.on('error', reject); });
  return hash.digest('base64');
}

let browser;
const errors = [], failedRequests = [], requests = [], pages = [];
const dump = async (page, name) => {
  await writeFile(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
  await page.screenshot({ path: path.join(output, name + '.png') });
};

try {
  browser = await chromium.launch({
    headless: true,
    executablePath: process.env.CHROME_PATH,
    args: ['--use-fake-device-for-media-stream', '--enable-precise-memory-info'],
  });
  for (let i = 0; i < 3; i++) {
    const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, locale: 'en-US', permissions: ['microphone', 'clipboard-read', 'clipboard-write'] });
    const page = await context.newPage();
    pages.push(page);
    page.setDefaultTimeout(20000);
    page.on('pageerror', e => errors.push(e.message));
    page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
    page.on('request', r => requests.push(r.url()));
    page.on('response', r => { if (r.status() >= 400) failedRequests.push(r.url()); });
    await page.goto(origin + '/?lang=en');
    await page.locator('flt-semantics-placeholder').waitFor();
    await page.locator('flt-semantics-placeholder').evaluate(el => el.click());
    await page.getByRole('heading', { name: /^Intragram/ }).waitFor();
    await page.locator('#app-loading').waitFor({ state: 'detached' });
  }
  const [a, b, c] = pages;
  const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const button = (page, name) => page.getByRole('button', { name: new RegExp(`^${esc(name)}(?: ${esc(name)})?$`) });
  const fill = async (page, field, value) => { await field.focus(); await page.waitForTimeout(150); await page.keyboard.press('ControlOrMeta+A'); await page.keyboard.insertText(value); await page.waitForTimeout(100); };
  const readCode = async page => { await button(page, 'Copy code').click(); const v = await page.evaluate(() => navigator.clipboard.readText()); assert.ok(v.startsWith('IGW1.')); return v; };
  const join = async (host, guest, add = false) => {
    await host.bringToFront();
    if (add) { await button(host, 'More').last().click(); await host.getByRole('menuitem', { name: 'Add people', exact: true }).click(); await button(host, 'Add').waitFor(); await button(host, 'Encrypted app–web connection').last().click(); }
    else await button(host, 'Encrypted app–web connection').first().click();
    await button(host, 'Create invitation code').click();
    await host.getByRole('textbox', { name: 'Your connection code', exact: true }).waitFor();
    const offer = await readCode(host);
    await guest.bringToFront();
    await button(guest, 'Encrypted app–web connection').first().click();
    await button(guest, 'Join with a code').click();
    await fill(guest, guest.getByRole('textbox', { name: 'Their invitation code', exact: true }), offer);
    await button(guest, 'Create response code').click();
    await guest.getByRole('textbox', { name: 'Your connection code', exact: true }).waitFor();
    const answer = await readCode(guest);
    await button(guest, 'Open conversation').click();
    await host.bringToFront();
    await fill(host, host.getByRole('textbox', { name: 'Their response code', exact: true }), answer);
    await button(host, 'Connect').click();
    for (const p of [host, guest]) {
      if (!add) await p.getByRole('heading', { name: /encrypted · code not checked/ }).waitFor();
      await p.getByRole('textbox', { name: 'Message', exact: true }).waitFor();
    }
  };
  const send = async (page, text) => {
    await page.bringToFront();
    await fill(page, page.getByRole('textbox', { name: 'Message', exact: true }), text);
    await page.keyboard.press('Enter');
  };
  const message = (page, text) => page.getByLabel(text, { exact: false });

  const sendClipText = async (page, text) => {
    await page.bringToFront();
    await page.evaluate(t => navigator.clipboard.writeText(t), text);
    await button(page, 'Send clipboard text').first().click();
    await button(page, 'Scrim').waitFor();
    await button(page, 'Send clipboard text').last().click();
    await button(page, 'Scrim').waitFor({ state: 'detached' });
  };

  // 1. Connect A <-> B: long inline text (>100 KiB), sending clipboard text, spillToFile
  await join(a, b);
  const longInline = 'LONG_HEAD_' + '장문패리티검증 🚀 한글 '.repeat(4500) + '_LONG_TAIL';
  assert.ok(Buffer.byteLength(longInline) > 110 * 1024);
  await sendClipText(a, longInline);
  await b.bringToFront();
  await b.getByLabel(/LONG_HEAD_/).waitFor({ timeout: 30000 });
  console.log('extended QA: >110 KiB inline multi-part UTF-8 sent from the clipboard passed');

  await a.bringToFront();
  await button(a, 'More').first().click();
  await a.getByRole('menuitem', { name: 'Settings', exact: true }).click();
  await a.getByText('As a file', { exact: true }).click();
  await button(a, 'Back').click();
  const spillText = 'SPILL_START_' + '파일전환모드검증 📝 '.repeat(4000) + '_SPILL_END';
  assert.ok(Buffer.byteLength(spillText) > 65536);
  await sendClipText(a, spillText);
  await b.bringToFront();
  await b.waitForTimeout(300);
  await button(b, 'Accept').waitFor({ timeout: 20000 });
  await button(b, 'Accept').click();
  const spillDl = b.waitForEvent('download');
  await b.getByRole('group', { name: /message\.txt/ }).getByRole('button', { name: 'Save to device', exact: true }).click();
  assert.equal((await readFile(await (await spillDl).path(), 'utf8')), spillText);
  await a.bringToFront();
  await button(a, 'More').first().click();
  await a.getByRole('menuitem', { name: 'Settings', exact: true }).click();
  await a.getByText('In memory', { exact: true }).click();
  await button(a, 'Back').click();
  console.log('extended QA: LargeMessageMode.spillToFile (>64 KiB -> message.txt) passed');

  // 2. 300 MiB synthetic file streaming over WebRTC + OPFS sink + bounded JS heap + exact SHA-256
  const bigSize = 300 * 1024 * 1024;
  const bigPath = path.join(tempFilesDir, 'synthetic-300mb.bin');
  const expectedSha256 = await generateSyntheticFile(bigPath, bigSize);
  const heapBeforeA = await a.evaluate(() => performance.memory?.usedJSHeapSize || 0);
  const heapBeforeB = await b.evaluate(() => performance.memory?.usedJSHeapSize || 0);
  await a.bringToFront();
  const sendFileBtn = page => page.getByRole('button', { name: /^Send a file(?: Send a file)?$/ }).last();
  const [bigChooser] = await Promise.all([
    a.waitForEvent('filechooser'),
    sendFileBtn(a).click(),
  ]);
  await bigChooser.setFiles(bigPath);
  await b.bringToFront();
  await button(b, 'Accept').waitFor({ timeout: 30000 });
  await button(b, 'Accept').click();
  const saveBigBtn = b.getByRole('group', { name: /synthetic-300mb\.bin/ }).getByRole('button', { name: 'Save to device', exact: true });
  await saveBigBtn.waitFor({ timeout: 180000 });
  const heapAfterA = await a.evaluate(() => performance.memory?.usedJSHeapSize || 0);
  const heapAfterB = await b.evaluate(() => performance.memory?.usedJSHeapSize || 0);
  assert.ok(heapAfterA - heapBeforeA < 100 * 1024 * 1024, `Sender JS heap grew too much: ${heapAfterA - heapBeforeA}`);
  assert.ok(heapAfterB - heapBeforeB < 100 * 1024 * 1024, `Receiver JS heap grew too much: ${heapAfterB - heapBeforeB}`);
  const bigDownload = b.waitForEvent('download', { timeout: 60000 });
  await saveBigBtn.click();
  const downloadedPath = await (await bigDownload).path();
  assert.equal((await stat(downloadedPath)).size, bigSize);
  assert.equal(await sha256File(downloadedPath), expectedSha256);
  await dump(b, 'stream-300mb-complete');
  console.log(`extended QA: 300 MiB browser-to-browser OPFS stream SHA-256 matched (heapA=${Math.round(heapAfterA / 1048576)}MB, heapB=${Math.round(heapAfterB / 1048576)}MB)`);

  // 3. Image preview + fullscreen ImageViewerScreen zoom + close
  const pngBase64 = await a.evaluate(() => {
    const c = document.createElement('canvas');
    c.width = 24;
    c.height = 24;
    const ctx = c.getContext('2d');
    ctx.fillStyle = '#2563eb';
    ctx.fillRect(0, 0, 24, 24);
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(6, 6, 12, 12);
    return c.toDataURL('image/png').split(',')[1];
  });
  const pngBytes = Buffer.from(pngBase64, 'base64');
  await a.bringToFront();
  await a.waitForTimeout(200);
  const [imgChooser] = await Promise.all([
    a.waitForEvent('filechooser'),
    sendFileBtn(a).click(),
  ]);
  await imgChooser.setFiles({ name: 'preview-test.png', mimeType: 'image/png', buffer: pngBytes });
  await b.bringToFront();
  await button(b, 'Accept').click();
  await b.getByRole('group', { name: /preview-test\.png/ }).getByRole('button', { name: 'Save to device', exact: true }).waitFor();
  await b.waitForTimeout(300);
  await b.getByRole('group', { name: /preview-test\.png/ }).getByRole('button').first().click();
  await button(b, 'Close').waitFor();
  await b.waitForTimeout(400);
  await dump(b, 'image-viewer-open');
  await button(b, 'Close').click();
  await button(b, 'Close').waitFor({ state: 'detached' });
  await b.waitForTimeout(300);
  console.log('extended QA: inline image thumbnail + fullscreen viewer passed');

  // 4. Reaction add/remove + Delete for me + Delete for everyone
  await send(a, 'Reaction and delete target');
  await b.bringToFront();
  await message(b, 'Reaction and delete target').waitFor();
  await message(b, 'Reaction and delete target').click({ button: 'right', force: true });
  await b.getByRole('button', { name: /^React with ❤️/ }).click();
  await b.waitForTimeout(450);
  await a.bringToFront();
  await a.getByRole('button', { name: /❤️/ }).waitFor();
  await b.bringToFront();
  await b.waitForTimeout(300);
  await b.getByRole('button', { name: /❤️/ }).click();
  await b.getByRole('button', { name: /❤️/ }).waitFor({ state: 'detached' });
  await a.bringToFront();
  await a.getByRole('button', { name: /❤️/ }).waitFor({ state: 'detached' });

  await send(a, 'Local delete only message');
  await b.bringToFront();
  await message(b, 'Local delete only message').waitFor();
  await message(b, 'Local delete only message').click({ button: 'right', force: true });
  await b.getByText('Delete for me', { exact: true }).click();
  await message(b, 'Local delete only message').waitFor({ state: 'detached' });
  await a.bringToFront();
  await message(a, 'Local delete only message').waitFor();

  await send(a, 'Global burn message');
  await b.bringToFront();
  await message(b, 'Global burn message').waitFor();
  await a.bringToFront();
  await message(a, 'Global burn message').click({ button: 'right', force: true });
  await a.getByRole('button', { name: /^Delete for everyone/ }).click();
  await message(a, 'Global burn message').waitFor({ state: 'detached' });
  await a.waitForTimeout(300);
  await b.bringToFront();
  await message(b, 'Global burn message').waitFor({ state: 'detached' });
  console.log('extended QA: reaction toggle + delete-for-me & delete-for-everyone passed');

  // 5. Org credential demo issue/present + Audit & Merkle Proofs bundle export/verify
  await a.bringToFront();
  await button(a, 'Organization credential not presented').click();
  await button(a, 'Issue and activate demo credential').click();
  await button(a, 'Stop presenting').waitFor();
  await button(a, 'Close').click();
  await b.bringToFront();
  await b.getByRole('button', { name: /Demo issuer · Demo Research Institute/ }).waitFor();
  await dump(b, 'org-credential-verified');

  await a.bringToFront();
  await button(a, 'More').last().click();
  await a.getByRole('menuitem', { name: 'Audit & Merkle Proofs', exact: true }).click();
  await button(a, 'Commit Merkle batch').click();
  // The batch row is one named group (it used to surface as a nameless read-only textbox on web).
  await a.getByRole('group', { name: /Merkle batch 1/ }).waitFor();
  await button(a, 'Copy JSON audit bundle').click();
  const bundleJson = await a.evaluate(() => navigator.clipboard.readText());
  assert.ok(bundleJson.includes('intragram-audit-anchor-bundle/v1'));
  await button(a, 'Export / verify external anchor bundle').click();
  await fill(a, a.getByLabel('Paste audit bundle or witness receipt JSON', { exact: true }), bundleJson);
  await button(a, 'Verify audit bundle').click();
  await a.getByText(/Bundle signatures and proofs verified/).first().waitFor();
  await dump(a, 'audit-bundle-verified');
  await button(a, 'Close').last().click();
  await a.waitForTimeout(300);
  await button(a, 'Close').first().click();
  await a.waitForTimeout(300);
  console.log('extended QA: Org demo credential + Audit Merkle batch & bundle verification passed');

  // 6. 3-tab group signed messaging, member leave, host end room
  await join(a, c, true);
  await a.bringToFront();
  await a.getByRole('heading', { name: /you host · 3 people/ }).waitFor();
  await send(c, 'Signed message from member C');
  await b.bringToFront();
  await message(b, 'Signed message from member C').waitFor();
  await c.bringToFront();
  await button(c, 'More').last().click();
  await c.getByRole('menuitem', { name: 'End conversation', exact: true }).click();
  await button(c, 'End').click();
  await a.bringToFront();
  await a.getByRole('heading', { name: /you host · 2 people/ }).waitFor();
  await send(a, 'After C left');
  await b.bringToFront();
  await message(b, 'After C left').waitFor();
  await a.bringToFront();
  await button(a, 'More').last().click();
  await a.getByRole('menuitem', { name: 'End conversation', exact: true }).click();
  await button(a, 'End').click();
  await a.getByText(/No chat open\./).waitFor();
  console.log('extended QA: group member leave and host end room passed');

  // 7. Duress PIN (decoy session preserves real vault) + Panic wipe (clears vault, chats, OPFS)
  await join(c, b);
  await send(c, 'Top secret vault message');
  await b.bringToFront();
  await message(b, 'Top secret vault message').waitFor();
  await button(b, 'More').first().click();
  await b.getByRole('menuitem', { name: 'Settings', exact: true }).click();
  await b.getByRole('switch', { name: /^Keep chats on this device/ }).click();
  await b.getByRole('button', { name: /^PIN-protect the saved file/ }).click();
  await fill(b, b.getByLabel('PIN', { exact: true }), 'realpin1');
  await fill(b, b.getByLabel('Confirm PIN', { exact: true }), 'realpin1');
  await button(b, 'Save').click();
  await b.waitForTimeout(400);
  await b.getByRole('button', { name: /^PIN-protect the saved file/ }).click();
  await b.getByText('Set a duress PIN', { exact: true }).click();
  await fill(b, b.getByLabel('PIN', { exact: true }).last(), 'decoypin2');
  await fill(b, b.getByLabel('Confirm PIN', { exact: true }).last(), 'decoypin2');
  await button(b, 'Save').last().click();
  await button(b, 'Cancel').first().click();
  await b.waitForTimeout(1500);

  // Reload and unlock with Duress PIN -> empty decoy session!
  await b.reload();
  await b.locator('flt-semantics-placeholder').waitFor();
  await b.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await b.getByText('Locked vault', { exact: true }).waitFor();
  await fill(b, b.getByLabel('PIN', { exact: true }), 'decoypin2');
  await button(b, 'Unlock').click();
  await b.getByRole('heading', { name: /^Intragram/ }).waitFor();
  await button(b, 'Search messages').click();
  await fill(b, b.getByLabel('Search messages', { exact: true }), 'Top secret vault message');
  await b.getByText(/No matches/).first().waitFor();
  await dump(b, 'duress-decoy-empty');

  // Reload and unlock with Real PIN -> secret message still intact!
  await b.reload();
  await b.locator('flt-semantics-placeholder').waitFor();
  await b.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await b.getByText('Locked vault', { exact: true }).waitFor();
  await fill(b, b.getByLabel('PIN', { exact: true }), 'realpin1');
  await button(b, 'Unlock').click();
  await b.getByRole('heading', { name: /^Intragram/ }).waitFor();
  await button(b, 'Search messages').click();
  await fill(b, b.getByLabel('Search messages', { exact: true }), 'Top secret vault message');
  await b.getByRole('button', { name: /Top secret vault message/ }).waitFor();
  await button(b, 'Back').click();
  await b.getByRole('heading', { name: /^Intragram/ }).waitFor();

  // Trigger Panic wipe -> rotates Ed25519 key, clears memory, vault, and OPFS temp files!
  await button(b, 'More').first().click();
  await b.getByRole('menuitem', { name: 'Panic wipe', exact: true }).click();
  await button(b, 'Wipe').click();
  const readVaultData = () => b.evaluate(() => new Promise((resolve, reject) => {
    const open = indexedDB.open('intragram-native-vault-v1', 1);
    open.onsuccess = () => { const db = open.result; const req = db.transaction('files').objectStore('files').getAll(); req.onsuccess = () => { resolve(req.result.map(raw => JSON.parse(raw).data).filter(v => v !== null)); db.close(); }; req.onerror = () => reject(req.error); };
    open.onerror = () => reject(open.error);
  }));
  let vaultAfterPanic = ['pending'];
  for (let i = 0; i < 40 && vaultAfterPanic.length > 0; i++) {
    await b.waitForTimeout(150);
    vaultAfterPanic = await readVaultData();
  }
  assert.deepEqual(vaultAfterPanic, []);
  await button(b, 'Search messages').click();
  await fill(b, b.getByLabel('Search messages', { exact: true }), 'Top secret vault message');
  await b.getByText(/No matches/).first().waitFor();
  await button(b, 'Back').click();
  const opfsRemaining = await b.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    try {
      const dir = await root.getDirectoryHandle('intragram-recv-tmp');
      const names = [];
      for await (const [name] of dir.entries()) names.push(name);
      return names;
    } catch { return []; }
  });
  assert.deepEqual(opfsRemaining, []);
  await dump(b, 'panic-wiped');
  console.log('extended QA: Duress PIN decoy + Real PIN restore + Panic wipe (memory, IndexedDB & OPFS cleared) passed');

  assert.deepEqual(errors, []);
  assert.deepEqual(failedRequests, []);
  assert.ok(requests.every(r => r.startsWith(origin + '/') || r.startsWith('blob:')));
  console.log('PASS: shared Flutter extended QA complete! Artifacts: ' + output);
} catch (error) {
  for (let i = 0; i < pages.length; i++) await dump(pages[i], 'ext-failure-' + i).catch(() => {});
  console.error('Extended QA failure artifacts: ' + output + '\nErrors: ' + JSON.stringify(errors) + '\nFailed requests: ' + JSON.stringify(failedRequests));
  throw error;
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
  await rm(tempFilesDir, { recursive: true, force: true }).catch(() => {});
}
