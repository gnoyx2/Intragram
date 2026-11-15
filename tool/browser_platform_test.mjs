// Compile tool/browser_platform_qa.dart to BROWSER_QA_BUILD before running.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const root = path.resolve(process.env.BROWSER_QA_BUILD || 'build/browser-qa');
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm',
  '.json': 'application/json', '.ttf': 'font/ttf', '.png': 'image/png' };
const server = createServer(async (request, response) => {
  try {
    const pathname = new URL(request.url, 'http://localhost').pathname;
    const file = path.resolve(root, '.' + decodeURIComponent(pathname) + (pathname.endsWith('/') ? 'index.html' : ''));
    if (!file.startsWith(root + path.sep)) throw Error('outside root');
    response.writeHead(200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream' });
    response.end(await readFile(file));
  } catch { response.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH });
try {
  const context = await browser.newContext({ acceptDownloads: true });
  const a = await context.newPage(), b = await context.newPage();
  const errors = [], requests = [];
  for (const page of [a, b]) {
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => requests.push(request.url()));
    await page.goto(origin);
    await page.waitForFunction(() => typeof window.intragramBrowserQA?.write === 'function');
  }
  await a.evaluate(() => window.intragramBrowserQA.write('first'));
  assert.equal(await a.evaluate(() => window.intragramBrowserQA.read()), 'first');
  await assert.rejects(b.evaluate(() => window.intragramBrowserQA.write('stale')));
  await b.evaluate(() => window.intragramBrowserQA.reload());
  assert.equal(await b.evaluate(() => window.intragramBrowserQA.read()), 'first');
  await b.evaluate(() => window.intragramBrowserQA.write('second'));
  await assert.rejects(a.evaluate(() => window.intragramBrowserQA.write('stale-again')));
  await a.evaluate(() => window.intragramBrowserQA.reload());
  await a.evaluate(() => window.intragramBrowserQA.erase());
  await assert.rejects(b.evaluate(() => window.intragramBrowserQA.write('must-not-resurrect')));
  await b.evaluate(() => window.intragramBrowserQA.reload());
  await assert.rejects(b.evaluate(() => window.intragramBrowserQA.read()));
  assert.match(await a.evaluate(() => window.intragramBrowserQA.vault()), /^PASS/);
  const file = await a.evaluate(() => window.intragramBrowserQA.files());
  assert.equal(await a.evaluate(path => window.intragramBrowserQA.contains(path), file), true);
  const download = a.waitForEvent('download');
  await a.evaluate(path => window.intragramBrowserQA.save(path), file);
  const saved = await download;
  assert.equal(saved.suggestedFilename(), '검증.bin');
  assert.deepEqual([...await readFile(await saved.path())], [0, 1, 2, 253, 254, 255]);
  await a.evaluate(() => window.intragramBrowserQA.clear());
  assert.equal(await a.evaluate(path => window.intragramBrowserQA.contains(path), file), false);
  await a.getByRole('button', { name: 'Run voice test', exact: true }).click();
  await a.waitForFunction(() => typeof window.intragramVoiceQA === 'string');
  assert.match(await a.evaluate(() => window.intragramVoiceQA), /^PASS/);
  // OPFS receive folders: one per tab under a Web Lock; a later start removes only folders whose
  // tab is gone (closed-tab leftovers, old flat files) and never a live tab's folder.
  const opfsNames = page => page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    let dir; try { dir = await root.getDirectoryHandle('intragram-recv-tmp'); } catch { return []; }
    const names = []; for await (const name of dir.keys()) names.push(name); return names.sort();
  });
  assert.equal(await a.evaluate(() => window.intragramBrowserQA.opfsSession()), true);
  assert.equal(await b.evaluate(() => window.intragramBrowserQA.opfsSession()), true);
  const live = await opfsNames(a);
  assert.equal(live.length, 2);
  await b.evaluate(async () => {
    const tmp = await (await navigator.storage.getDirectory()).getDirectoryHandle('intragram-recv-tmp');
    const stale = await tmp.getDirectoryHandle('feedfacecafebeef', { create: true });
    for (const [parent, name] of [[stale, 'recv-1-closed-tab.part'], [tmp, 'recv-0-old-flat.part']]) {
      const writable = await (await parent.getFileHandle(name, { create: true })).createWritable();
      await writable.write(new Uint8Array([1, 2, 3])); await writable.close();
    }
  });
  assert.equal((await opfsNames(a)).length, 4);
  await a.evaluate(() => window.intragramBrowserQA.opfsSweep());
  assert.deepEqual(await opfsNames(a), live);
  const heldLocks = () => a.evaluate(async () => (await navigator.locks.query()).held.map(l => l.name).filter(n => n.startsWith('intragram-recv-tmp-')));
  assert.equal((await heldLocks()).length, 2);
  await b.close();
  let held = await heldLocks();
  for (let i = 0; i < 50 && held.length !== 1; i++) { await a.waitForTimeout(100); held = await heldLocks(); }
  assert.equal(held.length, 1, 'closing a tab releases its folder lock');
  await a.evaluate(() => window.intragramBrowserQA.opfsSweep());
  assert.deepEqual(await opfsNames(a), [held[0].slice('intragram-recv-tmp-'.length)]);
  assert.deepEqual(errors, []);
  assert.ok(requests.every(url => url.startsWith(origin + '/') || url.startsWith('blob:')), 'no outside requests');
  console.log('PASS: shared native vault PIN/duress codec in browser, IndexedDB revision conflicts and tombstones, received file ownership/exact download/cleanup, actual shared WAV playback, per-tab OPFS receive folders removed only after their tab closed, no outside requests');
} finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
