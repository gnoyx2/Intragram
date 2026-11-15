// Shared Flutter web limits in a real browser: a file over the 64 GiB limit is refused with a
// notice and nothing is offered, a file exactly at the limit is offered, a voice recording stops
// by itself at two minutes and is sent, and in Unlimited mode a text over 64 MiB is refused while
// a near-64 MiB text arrives intact. The big files are sparse: they use no disk space.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdir, mkdtemp, open as openFile, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const root = path.resolve(process.env.SHARED_WEB_BUILD_DIR || fileURLToPath(new URL('../build/web/', import.meta.url)));
const output = process.env.WEB_QA_OUTPUT_DIR || await mkdtemp(path.join(tmpdir(), 'intragram-limits-qa-'));
await mkdir(output, { recursive: true });
const files = await mkdtemp(path.join(tmpdir(), 'intragram-limits-files-'));
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
const errors = [];
const log = msg => console.log('limits QA: ' + msg);
const dump = async (page, name) => {
  await writeFile(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
  await page.screenshot({ path: path.join(output, name + '.png') });
};
const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const button = (page, name) => page.getByRole('button', { name: new RegExp(`^${esc(name)}(?: ${esc(name)})?$`) });
const fill = async (page, field, value) => { await field.focus(); await page.waitForTimeout(150); await page.keyboard.press('ControlOrMeta+A'); await page.keyboard.insertText(value); await page.waitForTimeout(100); };
const readCode = async page => { await button(page, 'Copy code').click(); const v = await page.evaluate(() => navigator.clipboard.readText()); assert.ok(v.startsWith('IGW1.')); return v; };
const composer = page => page.getByRole('textbox', { name: 'Message', exact: true });
const tile = (page, name) => page.getByRole('group', { name: new RegExp(esc(name)) });
// 디스크를 쓰지 않는 sparse 파일
async function sparse(name, size) {
  const file = path.join(files, name), handle = await openFile(file, 'w');
  await handle.truncate(size);
  await handle.close();
  const info = await stat(file);
  assert.equal(info.size, size);
  assert.ok(info.blocks * 512 < 1024 * 1024, `${name} must stay sparse`);
  return file;
}
async function open(name) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, locale: 'en-US', permissions: ['microphone', 'clipboard-read', 'clipboard-write'] });
  const page = await context.newPage();
  page.setDefaultTimeout(20000);
  page.on('pageerror', e => errors.push(`${name}: ${e.message}`));
  page.on('console', m => { if (m.type() === 'error') errors.push(`${name}: ${m.text()}`); });
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
async function attach(page, selected) {
  await page.bringToFront();
  const [chooser] = await Promise.all([page.waitForEvent('filechooser'), button(page, 'Send a file').last().click()]);
  await chooser.setFiles(selected);
}

try {
  const GiB = 1024 ** 3;
  const over = await sparse('over-limit.bin', 64 * GiB + 1), exact = await sparse('at-limit.bin', 64 * GiB);
  const small = path.join(files, 'small-next-to-big.txt');
  await writeFile(small, 'sent although the other file was refused');
  browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH, args: ['--use-fake-device-for-media-stream'] });
  const a = await open('A'), b = await open('B');
  await link(a, b);
  await a.bringToFront();
  await composer(a).waitFor();

  // 1. Over the limit: a notice, no offer on either side. A smaller file picked with it still goes.
  await attach(a, [over, small]);
  await a.getByText(/Files over 64 GiB cannot be sent over an encrypted web connection/).first().waitFor();
  await dump(a, 'over-limit-refused');
  await b.bringToFront();
  await tile(b, 'small-next-to-big.txt').waitFor();
  assert.equal(await tile(a, 'over-limit.bin').count(), 0, 'no transfer tile for the refused file on the sender');
  assert.equal(await tile(b, 'over-limit.bin').count(), 0, 'the peer is never offered the refused file');
  log('a file of 64 GiB + 1 byte is refused with a notice; the small file picked with it is still offered');

  // 2. Exactly at the limit: offered (nothing is read before the peer accepts). Cancelled again.
  await attach(a, [exact]);
  await b.bringToFront();
  await tile(b, 'at-limit.bin').waitFor();
  await a.bringToFront();
  await tile(a, 'at-limit.bin').getByRole('button', { name: /^Cancel/ }).first().click();
  await b.bringToFront();
  await tile(b, 'at-limit.bin').getByRole('button', { name: 'Accept', exact: true }).waitFor({ state: 'detached' });
  log('a file of exactly 64 GiB is offered and can be cancelled');

  // 3. Unlimited mode 64 MiB text ceiling: > 64 MiB is refused locally; near-64 MiB arrives intact.
  const setLargeMode = async (page, mode) => {
    await page.bringToFront();
    await button(page, 'More').first().click();
    await page.getByRole('menuitem', { name: 'Settings', exact: true }).click();
    await page.getByText(mode, { exact: true }).click();
    await button(page, 'Back').click();
    await page.getByText('Large messages', { exact: true }).waitFor({ state: 'detached' });
  };
  const sendClip = async page => {
    await page.bringToFront();
    await button(page, 'Send clipboard text').first().click();
    await button(page, 'Scrim').waitFor();
    await button(page, 'Send clipboard text').last().click();
    await button(page, 'Scrim').waitFor({ state: 'detached' });
  };
  await setLargeMode(a, 'Unlimited');
  await setLargeMode(b, 'Unlimited');

  const overBytes = 64 * 1024 * 1024 + 64;
  await a.bringToFront();
  await a.evaluate(n => {
    const head = 'OVER64M_HEAD_';
    return navigator.clipboard.writeText(head + 'X'.repeat(n - head.length));
  }, overBytes);
  await sendClip(a);
  const failedBubble = a.getByRole('button', { name: /^From you\s+Long message\.[\s\S]*OVER64M_HEAD_[\s\S]*failed to send/ });
  await failedBubble.waitFor({ timeout: 60000 });
  await dump(a, 'over-64mib-text-refused');
  await b.bringToFront();
  assert.equal(await b.getByLabel(/OVER64M_HEAD_/).count(), 0, 'text over 64 MiB is never delivered to the peer');
  log(`Unlimited mode refused a ${overBytes} B (> 64 MiB) text locally and sent nothing to the peer`);

  const nearBytes = 64 * 1024 * 1024 - 64;
  const heapBeforeA = await a.evaluate(() => performance.memory?.usedJSHeapSize || 0);
  const heapBeforeB = await b.evaluate(() => performance.memory?.usedJSHeapSize || 0);
  await a.bringToFront();
  await a.evaluate(n => {
    const head = 'NEAR64M_HEAD_', tail = '_NEAR64M_TAIL';
    return navigator.clipboard.writeText(head + 'U'.repeat(n - head.length - tail.length) + tail);
  }, nearBytes);
  const textStarted = Date.now();
  await sendClip(a);
  await b.bringToFront();
  const nearBubble = b.getByLabel(/NEAR64M_HEAD_/).first();
  await nearBubble.waitFor({ timeout: 120000 });
  const textSeconds = (Date.now() - textStarted) / 1000;
  const box = await nearBubble.boundingBox();
  await b.mouse.click(box.x + box.width / 2, Math.max(180, Math.min(700, box.y + 40)), { button: 'right' });
  await b.getByRole('menuitem', { name: 'Copy text' }).or(b.getByRole('button', { name: 'Copy text' })).first().click();
  const copiedMeta = await b.evaluate(async () => {
    const t = await navigator.clipboard.readText();
    return { len: t.length, head: t.slice(0, 13), tail: t.slice(-13) };
  });
  assert.deepEqual(copiedMeta, { len: nearBytes, head: 'NEAR64M_HEAD_', tail: '_NEAR64M_TAIL' });
  const heapAfterA = await a.evaluate(() => performance.memory?.usedJSHeapSize || 0);
  const heapAfterB = await b.evaluate(() => performance.memory?.usedJSHeapSize || 0);
  await dump(b, 'near-64mib-text-received');
  log(
    `Unlimited mode sent and received ${nearBytes} B (~64 MiB) text in ${textSeconds.toFixed(2)} s ` +
    `(JS heap A: ${(heapBeforeA / 1048576).toFixed(1)} -> ${(heapAfterA / 1048576).toFixed(1)} MiB, ` +
    `B: ${(heapBeforeB / 1048576).toFixed(1)} -> ${(heapAfterB / 1048576).toFixed(1)} MiB)`
  );

  // 4. A hands-free recording stops by itself at two minutes and is sent. The security code is
  //    confirmed first, as in the other voice checks (after the file steps, so nothing auto-accepts them).
  for (const p of [a, b]) {
    await p.bringToFront();
    await button(p, 'Check security code').click();
    await button(p, 'They match').click();
  }
  for (const p of [a, b]) await button(p, 'Security code verified').waitFor();
  await a.bringToFront();
  const started = Date.now();
  await button(a, 'Tap to record hands-free, or hold to record while pressed').click();
  await button(a, 'Recording. Double tap to send.').waitFor();
  await button(a, 'Recording. Double tap to send.').waitFor({ state: 'detached', timeout: 140000 });
  const seconds = (Date.now() - started) / 1000;
  assert.ok(seconds > 117 && seconds < 127, `recording stopped by itself after ${seconds.toFixed(1)} s`);
  await b.bringToFront();
  const voice = b.getByRole('group', { name: /^From .* \d:\d\d Encrypted/ }).last();
  try { await voice.waitFor({ timeout: 60000 }); }
  catch (error) { await dump(a, 'voice-timeout-sender'); await dump(b, 'voice-timeout-receiver'); throw error; }
  const download = b.waitForEvent('download');
  await voice.getByRole('button', { name: /^Save to device(?: Save to device)?$/ }).click();
  const wav = await readFile(await (await download).path());
  const audioSeconds = (wav.length - 44) / (16000 * 2);
  assert.deepEqual([wav.toString('ascii', 0, 4), wav.readUInt32LE(24), wav.readUInt16LE(34)], ['RIFF', 16000, 16]);
  assert.ok(audioSeconds > 119 && audioSeconds <= 120.5, `received ${audioSeconds.toFixed(2)} s of audio`);
  assert.ok(wav.length <= 4 * 1024 * 1024, 'within the 4 MiB voice bound');
  await dump(b, 'two-minute-voice-received');
  log(`recording stopped by itself after ${seconds.toFixed(1)} s and arrived as ${audioSeconds.toFixed(2)} s of 16 kHz audio (${wav.length} B)`);

  assert.deepEqual(errors, []);
  console.log('PASS: limits QA complete. Artifacts: ' + output);
} catch (error) {
  console.error('limits QA failure artifacts: ' + output + '\nErrors: ' + JSON.stringify(errors));
  throw error;
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
  await rm(files, { recursive: true, force: true });
}
