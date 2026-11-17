import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, mkdir, mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
// Errors are tagged with the last finished step so an intermittent one can be placed.
let step = 'start';
const print = console.log;
console.log = (...args) => { step = String(args[0]).slice(0, 80); print(...args); };
const root = path.resolve(process.env.SHARED_WEB_BUILD_DIR || fileURLToPath(new URL('../build/web/', import.meta.url)));
const output = process.env.WEB_QA_OUTPUT_DIR || await mkdtemp(path.join(tmpdir(), 'intragram-shared-flutter-'));
await mkdir(output, { recursive: true });
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.ttf': 'font/ttf' };
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
const errors = [], requests = [], failedRequests = [], pages = [];
const dump = async (page, name) => {
  await writeFile(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
  await page.screenshot({ path: path.join(output, name + '.png') });
  await writeFile(path.join(output, name + '.html'), await page.content());
};
try {
  browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH, args: ['--use-fake-device-for-media-stream'] });
  for (let i = 0; i < 3; i++) {
    const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, locale: 'en-US', permissions: ['microphone', 'clipboard-read', 'clipboard-write'] });
    const page = await context.newPage();
    pages.push(page);
    page.setDefaultTimeout(15000);
    // 대화가 있는 새로고침은 앱이 브라우저 확인을 띄움: 그 확인만 수락 (나머지 대화상자는 기본처럼 닫음)
    page.on('dialog', d => d.type() === 'beforeunload' ? d.accept() : d.dismiss());
    page.on('pageerror', error => errors.push(`[after ${step}] ${error.message}`));
    page.on('console', message => { if (message.type() === 'error') errors.push(`[after ${step}] ${message.text()}`); });
    page.on('request', request => requests.push(request.url()));
    page.on('response', response => { if (response.status() >= 400) failedRequests.push(response.url()); });
    await page.goto(origin + '/?lang=en');
    await page.locator('flt-semantics-placeholder').waitFor();
    await page.locator('flt-semantics-placeholder').evaluate(element => element.click());
    await page.getByRole('heading', { name: /^Intragram/ }).waitFor();
    await page.locator('#app-loading').waitFor({ state: 'detached' });
  }
  const [a, b, c] = pages;
  await dump(a, 'home');
  const button = (page, name) => page.getByRole('button', { name, exact: true });
  const play = page => page.getByRole('button', { name: /^Play(?: Play)?$/ });
  const pause = page => page.getByRole('button', { name: /^Pause(?: Pause)?$/ });
  const fill = async (page, field, value) => { await field.focus(); await page.waitForTimeout(150); await page.keyboard.press('ControlOrMeta+A'); await page.keyboard.insertText(value); await page.waitForTimeout(100); };
  const code = async page => { await button(page, 'Copy code').click(); const value = await page.evaluate(() => navigator.clipboard.readText()); assert.ok(value.startsWith('IGW1.')); return value; };
  const join = async (host, guest, add = false) => {
    await host.bringToFront();
    if (add) { await button(host, 'More').last().click(); await host.getByRole('menuitem', { name: 'Add people', exact: true }).click(); await button(host, 'Add').waitFor(); await button(host, 'Encrypted app–web connection').last().click(); }
    else await button(host, 'Encrypted app–web connection').first().click();
    await button(host, 'Create invitation code').click();
    const hostCode = host.getByRole('textbox', { name: 'Your connection code', exact: true });
    await hostCode.waitFor();
    const offer = await code(host);
    assert.ok(offer.startsWith('IGW1.'));
    await guest.bringToFront();
    await button(guest, 'Encrypted app–web connection').first().click();
    await button(guest, 'Join with a code').click();
    await fill(guest, guest.getByRole('textbox', { name: 'Their invitation code', exact: true }), offer);
    await button(guest, 'Create response code').click();
    const guestCode = guest.getByRole('textbox', { name: 'Your connection code', exact: true });
    await guestCode.waitFor();
    const answer = await code(guest);
    assert.notEqual(answer, offer);
    assert.ok(answer.startsWith('IGW1.'));
    await button(guest, 'Open conversation').click();
    await host.bringToFront();
    await fill(host, host.getByRole('textbox', { name: 'Their response code', exact: true }), answer);
    await button(host, 'Connect').click();
    for (const page of [host, guest]) {
      if (!add) await page.getByRole('heading', { name: /encrypted · code not checked/ }).waitFor();
      await page.getByRole('textbox', { name: 'Message', exact: true }).waitFor();
    }
  };
  const send = async (page, text) => {
    await page.bringToFront();
    await fill(page, page.getByRole('textbox', { name: 'Message', exact: true }), text);
    await page.keyboard.press('Enter');
  };
  const openSettings = async page => {
    await page.bringToFront();
    await button(page, 'More').first().click();
    await page.getByRole('menuitem', { name: 'Settings', exact: true }).click();
    await page.mouse.move(900, 700); await page.mouse.wheel(0, 900);
  };
  const chooseSetting = async (page, label, value) => {
    await page.getByRole('button', { name: label }).click();
    await page.getByRole('menuitem', { name: value, exact: true }).click();
  };
  await openSettings(c);
  for (const theme of ['Light', 'Dark', 'System']) {
    await chooseSetting(c, /^Appearance /, theme);
    await c.getByRole('button', { name: 'Appearance ' + theme, exact: true }).waitFor();
    await dump(c, 'settings-en-' + theme.toLowerCase());
  }
  await chooseSetting(c, /^Language /, '한국어');
  await c.getByRole('heading', { name: '설정', exact: true }).waitFor();
  for (const theme of ['라이트', '다크', '시스템']) {
    await chooseSetting(c, /^테마 /, theme);
    await c.getByRole('button', { name: '테마 ' + theme, exact: true }).waitFor();
    await dump(c, 'settings-ko-' + theme);
  }
  await chooseSetting(c, /^언어 /, 'English');
  await chooseSetting(c, /^Text size /, '200%');
  await c.waitForTimeout(300);
  await c.mouse.move(900, 700); await c.mouse.wheel(0, 2500);
  await c.getByRole('button', { name: /^Text size .*200%$/ }).waitFor();
  await dump(c, 'settings-200-percent');
  await button(c, 'Back').click();
  console.log('shared Flutter: KO/EN, light/dark/system settings and 200% text selected through UI');
  await join(a, b);
  // Autofill stays off: no engine <form> (its placement race throws on web) and no browser autocomplete.
  await a.bringToFront();
  await a.getByRole('textbox', { name: 'Message', exact: true }).focus();
  await a.waitForTimeout(200);
  assert.deepEqual(await a.evaluate(() => ({ inForm: !!document.activeElement?.closest('form'), autocomplete: document.activeElement?.getAttribute('autocomplete') })), { inForm: false, autocomplete: 'off' });
  await send(a, 'Shared Flutter message <script>');
  await b.bringToFront();
  await b.getByText(/Shared Flutter message <script>/).waitFor();
  const message = (page, text) => page.getByLabel(text, { exact: false });
  await dump(b, 'before-actions');
  await b.bringToFront();
  await message(b, 'Shared Flutter message <script>').click({ button: 'right', force: true });
  await dump(b, 'message-actions');
  await b.getByText('Reply', { exact: true }).click();
  await send(b, 'Reply from the shared app');
  await a.bringToFront();
  await message(a, 'Reply from the shared app').waitFor();
  await message(a, 'Reply from the shared app').click({ button: 'right', force: true });
  await a.getByRole('button', { name: /^React with 👍/ }).click();
  await b.bringToFront();
  await b.getByRole('button', { name: /👍/ }).waitFor();
  await a.bringToFront();
  assert.match(await a.getByLabel(/^From you\nShared Flutter message/).getAttribute('aria-label'), /read/);
  await button(a, 'Self-destruct timer').click();
  await a.getByRole('menuitem', { name: 'Burn after 5s', exact: true }).click();
  await send(a, 'This message expires after five seconds');
  await b.bringToFront();
  await message(b, 'This message expires after five seconds').waitFor();
  await message(b, 'This message expires after five seconds').waitFor({ state: 'detached', timeout: 10000 });
  await a.bringToFront();
  await button(a, 'Self-destruct timer').click();
  await a.getByRole('menuitem', { name: 'Timer off', exact: true }).click();
  await button(a, 'Check security code').click();
  await button(a, 'They match').waitFor();
  const sasA = (await a.locator('body').ariaSnapshot()).match(/\d \d \d, \d \d \d/)?.[0];
  await button(a, 'They match').click();
  await b.bringToFront();
  await button(b, 'Check security code').click();
  await button(b, 'They match').waitFor();
  const sasB = (await b.locator('body').ariaSnapshot()).match(/\d \d \d, \d \d \d/)?.[0];
  assert.ok(sasA); assert.equal(sasA, sasB);
  await button(b, 'They match').click();
  await button(b, 'Security code verified').waitFor();
  await a.bringToFront();
  await button(a, 'Security code verified').waitFor();
  await a.bringToFront();
  await button(a, 'Tap to record hands-free, or hold to record while pressed').click();
  await button(a, 'Recording. Double tap to send.').waitFor();
  await dump(a, 'voice-recording');
  await a.waitForTimeout(1400);
  await button(a, 'Send').last().click();
  for (const page of [a, b]) {
    await page.bringToFront();
    await play(page).waitFor();
    await play(page).click();
    await page.mouse.move(10, 10);
    await pause(page).waitFor();
    await pause(page).click();
    await page.mouse.move(10, 10);
    await play(page).waitFor();
    await dump(page, page === a ? 'voice-sender' : 'voice-receiver');
  }
  console.log('shared Flutter: microphone recording, send, and playback on both peers passed');
  const playsBeforeCancel = await play(b).count();
  await a.bringToFront();
  await button(a, 'Tap to record hands-free, or hold to record while pressed').click();
  await button(a, 'Recording. Double tap to send.').waitFor();
  await a.waitForTimeout(900);
  await button(a, 'Tap to cancel').click();
  await button(a, 'Recording. Double tap to send.').waitFor({ state: 'detached' });
  await a.waitForTimeout(300);
  assert.equal(await play(b).count(), playsBeforeCancel);
  await dump(a, 'voice-cancelled');
  await a.context().clearPermissions();
  await a.context().grantPermissions(['clipboard-read', 'clipboard-write'], { origin });
  assert.equal(await a.evaluate(async () => (await navigator.permissions.query({ name: 'microphone' })).state), 'denied');
  await button(a, 'Tap to record hands-free, or hold to record while pressed').click();
  await a.getByText(/Microphone access is off for Intragram/).waitFor();
  assert.equal(await button(a, 'Recording. Double tap to send.').count(), 0);
  await dump(a, 'voice-permission-denied');
  await a.context().grantPermissions(['microphone', 'clipboard-read', 'clipboard-write'], { origin });
  await button(a, 'Tap to record hands-free, or hold to record while pressed').click();
  await button(a, 'Recording. Double tap to send.').waitFor();
  // Playwright keeps every page "focused and visible" through CDP focus
  // emulation, and each Playwright page is its own window, so a tab switch can
  // never set document.hidden here. Turn the emulation off so the browser
  // delivers its real window blur when another page takes the foreground;
  // Flutter maps that to a non-resumed lifecycle exactly like native desktop.
  const focusSession = await a.context().newCDPSession(a);
  await focusSession.send('Emulation.setFocusEmulationEnabled', { enabled: false });
  await a.evaluate(() => { window.__igBlur = false; window.addEventListener('blur', () => { window.__igBlur = true; }, { once: true }); });
  const background = await a.context().newPage();
  await background.bringToFront();
  await a.waitForFunction(() => window.__igBlur === true && !document.hasFocus());
  await a.waitForTimeout(300);
  await a.bringToFront(); await background.close();
  await focusSession.send('Emulation.setFocusEmulationEnabled', { enabled: true });
  await focusSession.detach();
  await button(a, 'Recording. Double tap to send.').waitFor({ state: 'detached' });
  assert.equal(await play(b).count(), playsBeforeCancel);
  await dump(a, 'voice-background-cancelled');
  console.log('shared Flutter: explicit recording cancel, microphone denial/recovery, and real window-blur (page background) cancellation passed');

  const payload = Buffer.from('Shared Flutter encrypted file bytes\n');
  const chooser = a.waitForEvent('filechooser');
  await button(a, 'Send a file').click();
  await (await chooser).setFiles({ name: 'shared-flutter.txt', mimeType: 'text/plain', buffer: payload });
  await b.bringToFront();
  await button(b, 'Accept').click();
  const download = b.waitForEvent('download');
  await b.getByRole('group', { name: /shared-flutter\.txt/ }).getByRole('button', { name: 'Save to device', exact: true }).click();
  assert.deepEqual(await readFile(await (await download).path()), payload);
  await dump(a, 'chat-a'); await dump(b, 'chat-b');
  await b.getByRole('button', { name: 'More', exact: true }).last().click();
  await b.getByRole('menuitem', { name: 'Search in chat', exact: true }).click();
  await fill(b, b.getByRole('textbox', { name: 'Search in chat', exact: true }), 'Reply from');
  await b.getByText('1/1', { exact: true }).waitFor();
  await dump(b, 'search');
  await button(b, 'Close search').click();
  await join(a, c, true);
  await send(b, 'Group message through the shared host');
  await c.bringToFront();
  await message(c, 'Group message through the shared host').waitFor();
  await send(c, 'Third browser reply');
  await b.bringToFront();
  await message(b, 'Third browser reply').waitFor();
  await dump(c, 'group');
  const groupPayload = Buffer.from('그룹 파일: independent recipient consent\n');
  const groupChooser = b.waitForEvent('filechooser');
  await button(b, 'Send a file').click();
  await (await groupChooser).setFiles({ name: '그룹.txt', mimeType: 'text/plain', buffer: groupPayload });
  await a.bringToFront();
  await button(a, 'Accept').click();
  await c.bringToFront();
  await button(c, 'Accept').click();
  const groupDownload = c.waitForEvent('download');
  await button(c, 'Save to device').click();
  assert.deepEqual(await readFile(await (await groupDownload).path()), groupPayload);
  await dump(c, 'group-file');
  for (const width of [320, 390, 768, 1024, 1440]) {
    await c.bringToFront();
    await c.setViewportSize({ width, height: 844 });
    await c.waitForTimeout(300);
    const box = await button(c, 'Send').boundingBox();
    assert.ok(box && box.x >= 0 && box.x + box.width <= width && box.y + box.height <= 844);
    await dump(c, 'group-' + width);
  }

  await openSettings(c);
  await c.mouse.wheel(0, 2000);
  await chooseSetting(c, /^Text size /, '100%');
  await button(c, 'Back').click();
  console.log('shared Flutter: 200% conversation composer remains reachable at 320/390/768/1024/1440px');

  await join(c, b);
  await send(c, 'Private conversation kept in the native vault');
  await b.bringToFront();
  await message(b, 'Private conversation kept in the native vault').waitFor();
  await b.getByRole('button', { name: 'More', exact: true }).first().click();
  await b.getByRole('menuitem', { name: 'Settings', exact: true }).click();
  await b.getByRole('switch', { name: /^Keep chats on this device/ }).click();
  await b.getByRole('button', { name: /^PIN-protect the saved file/ }).click();
  await fill(b, b.getByLabel('PIN', { exact: true }), 'vault789');
  await fill(b, b.getByLabel('Confirm PIN', { exact: true }), 'vault789');
  await button(b, 'Save').click();
  await b.getByRole('button', { name: /^PIN-protect the saved file/ }).waitFor();
  await dump(b, 'settings');
  const records = page => page.evaluate(() => new Promise((resolve, reject) => {
    const open = indexedDB.open('intragram-native-vault-v1', 1);
    open.onsuccess = () => { const db = open.result; const request = db.transaction('files').objectStore('files').getAll(); request.onsuccess = () => { resolve(request.result); db.close(); }; request.onerror = () => reject(request.error); };
    open.onerror = () => reject(open.error);
  }));
  let saved;
  for (let i = 0; i < 30; i++) {
    saved = await records(b);
    if (saved.some(raw => { try { return JSON.parse(JSON.parse(raw).data).enc === true; } catch { return false; } })) break;
    await b.waitForTimeout(100);
  }
  assert.ok(saved.some(raw => { try { return JSON.parse(JSON.parse(raw).data).enc === true; } catch { return false; } }));
  assert.ok(saved.every(raw => !raw.includes('Private conversation kept in the native vault')));
  await b.reload();
  await b.locator('flt-semantics-placeholder').waitFor();
  await b.locator('flt-semantics-placeholder').evaluate(element => element.click());
  await b.getByText('Locked vault', { exact: true }).waitFor();
  await fill(b, b.getByLabel('PIN', { exact: true }), 'wrong789');
  await button(b, 'Unlock').click();
  await b.getByText('Wrong PIN', { exact: true }).waitFor();
  assert.deepEqual(await records(b), saved);
  await fill(b, b.getByLabel('PIN', { exact: true }), 'vault789');
  await button(b, 'Unlock').click();
  await b.getByRole('heading', { name: /^Intragram/ }).waitFor();
  await button(b, 'Search messages').click();
  // An autofocused field also has Flutter's hidden editing input with the same placeholder.
  await fill(b, b.locator('[data-semantics-role="text-field"][aria-label="Search messages"]'), 'Private conversation kept in the native vault');
  await b.getByRole('button', { name: /Private conversation kept in the native vault/ }).click();
  await message(b, 'Private conversation kept in the native vault').waitFor();
  await dump(b, 'vault-restored-search');


  if (process.env.SHARED_QA_PROBE) { console.log('PROBE: ' + output + ' errors=' + JSON.stringify(errors)); }
  else {
    assert.deepEqual(errors, []);
    assert.deepEqual(failedRequests, []);
    assert.ok(requests.every(request => request.startsWith(origin + '/') || request.startsWith('blob:')));
    console.log('PASS: shared Flutter UI: three-browser codes/SAS/text/reply/reaction/read/burn, file and group relay exact downloads, recorded WAV send/play on both peers, cancel/permission/background, KO/EN/themes/200% 320–1440px, PIN setup/wrong/correct unlock and restored search; no failed/external requests. Screenshots: ' + output);
  }
} catch (error) {
  for (let i = 0; i < pages.length; i++) await dump(pages[i], 'failure-' + i).catch(() => {});
  console.error('Shared Flutter test artifacts: ' + output + '\nRuntime errors: ' + JSON.stringify(errors) + '\nFailed requests: ' + JSON.stringify(failedRequests) + '\nExternal requests: ' + JSON.stringify(requests.filter(request => !request.startsWith(origin + '/') && !request.startsWith('blob:'))));
  throw error;
} finally { await browser?.close(); await new Promise(resolve => server.close(resolve)); }
