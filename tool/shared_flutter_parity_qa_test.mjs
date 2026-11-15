// Shared Flutter web parity QA: two files flowing at once (lanes), the composer keeps its name
// while it has text, jump from a reply quote to the original, a failed send retried after the
// peer is added back, a content-free browser notification while the tab is in the background,
// a sanitized RLO file name, a decompression-bomb image, and a group member who leaves and rejoins.
// Real UI in isolated Chromium contexts. QA code only observes (a Notification constructor log).
import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { createServer } from 'node:http';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const root = path.resolve(process.env.SHARED_WEB_BUILD_DIR || fileURLToPath(new URL('../build/web/', import.meta.url)));
const output = process.env.WEB_QA_OUTPUT_DIR || await mkdtemp(path.join(tmpdir(), 'intragram-parity-qa-'));
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
const log = msg => console.log('parity QA: ' + msg);
const sha = b => createHash('sha256').update(b).digest('hex');
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
const tile = (page, name) => page.getByRole('group', { name: new RegExp(esc(name)) });
// 메시지 동작 메뉴: 스크린 리더와 같은 경로 (호버 막대는 마우스 전용이라 접근성 트리에 없음).
// Flutter가 포인터를 받는 flutter-view 위 좌표로 우클릭함
const messageAction = async (page, locator, item) => {
  const box = await locator.first().boundingBox();
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2, { button: 'right' });
  await page.getByRole('menuitem', { name: item, exact: true }).or(page.getByRole('button', { name: item, exact: true })).first().click();
};
const inView = async (locator, height) => {
  if (await locator.count() === 0) return false;
  const box = await locator.first().boundingBox();
  return !!box && box.y >= 0 && box.y + box.height <= height;
};
async function open(name, { notifications = false } = {}) {
  const permissions = ['microphone', 'clipboard-read', 'clipboard-write', ...(notifications ? ['notifications'] : [])];
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, locale: 'en-US', permissions });
  // 관찰만 함: 앱이 만든 알림의 제목·본문을 기록하고 진짜 Notification을 그대로 만듦
  await context.addInitScript(() => {
    const Real = window.Notification;
    if (!Real) return;
    window.__igNotes = [];
    class Logged extends Real {
      constructor(title, options) { super(title, options); window.__igNotes.push({ title, body: options?.body ?? '' }); }
      static get permission() { return Real.permission; }
      static requestPermission(...args) { return Real.requestPermission(...args); }
    }
    window.Notification = Logged;
  });
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
// host가 새 링크를 염: add면 열린 대화의 '사람 추가', 아니면 홈의 새 연결
async function link(host, guest, { add = false } = {}) {
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
async function sendClipText(page, text) {
  await page.bringToFront();
  await page.evaluate(t => navigator.clipboard.writeText(t), text);
  await button(page, 'Send clipboard text').first().click();
  await button(page, 'Scrim').waitFor();
  await button(page, 'Send clipboard text').last().click();
  await button(page, 'Scrim').waitFor({ state: 'detached' });
}
async function largeMessages(page, mode) {
  await page.bringToFront();
  await button(page, 'More').first().click();
  await page.getByRole('menuitem', { name: 'Settings', exact: true }).click();
  await page.getByText(mode, { exact: true }).click();
  await button(page, 'Back').click();
  await page.getByText('Large messages', { exact: true }).waitFor({ state: 'detached' });
  await page.waitForTimeout(400);
}
async function endChat(page) {
  await page.bringToFront();
  await button(page, 'More').last().click();
  await page.getByRole('menuitem', { name: 'End conversation', exact: true }).click();
  await page.getByRole('alertdialog').getByRole('button', { name: 'End', exact: true }).click();
}

try {
  browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH, args: ['--use-fake-device-for-media-stream'] });
  const a = await open('A'), b = await open('B', { notifications: true });
  await link(a, b);
  await verify(a, b);
  log('A and B connected with a verified security code');

  // 1. Composer keeps its accessible name while it holds a draft (it used to become nameless).
  await b.bringToFront();
  await fill(b, composer(b), 'draft 초안 ✍️');
  await b.waitForTimeout(300);
  assert.equal(await composer(b).count(), 1, 'composer still named "Message" with a draft');
  assert.equal(await composer(b).inputValue(), 'draft 초안 ✍️');
  await b.keyboard.press('ControlOrMeta+A'); await b.keyboard.press('Backspace');
  log('composer keeps the name "Message" while it has text');

  // 2. Lanes: a small file accepted after a big one finishes while the big one still flows.
  const bigPath = path.join(output, 'big.bin');
  const big = Buffer.concat(Array.from({ length: 64 }, () => randomBytes(1 << 20)));
  await writeFile(bigPath, big);
  const small = Buffer.from('small file overtakes the big one 작은 파일\n');
  await attach(a, bigPath);
  await attach(a, { name: 'small.txt', mimeType: 'text/plain', buffer: small });
  await b.bringToFront();
  await tile(b, 'big.bin').getByRole('button', { name: 'Accept', exact: true }).click();
  await tile(b, 'small.txt').getByRole('button', { name: 'Accept', exact: true }).click();
  await tile(b, 'small.txt').getByRole('button', { name: 'Save to device', exact: true }).waitFor();
  assert.equal(await tile(b, 'big.bin').getByRole('button', { name: 'Save to device', exact: true }).count(), 0,
    'the big file is still transferring when the small one is done');
  await dump(b, 'lanes-small-done-big-flowing');
  assert.deepEqual(await saved(b, 'small.txt'), small);
  await tile(b, 'big.bin').getByRole('button', { name: 'Save to device', exact: true }).waitFor({ timeout: 180000 });
  assert.equal(sha(await saved(b, 'big.bin')), sha(big));
  log('two files flowed at once: small.txt finished first, big.bin (64 MiB) SHA-256 matches');

  // 3. Jump from a reply quote to the original, far above in the list.
  const original = 'Original message for the jump test';
  await send(a, original);
  for (let i = 1; i <= 30; i++) await send(a, `filler message ${i}`);
  await b.bringToFront();
  await message(b, 'filler message 30').waitFor();
  await b.mouse.move(1000, 500);
  for (let i = 0; i < 20 && !(await inView(message(b, original), 1000)); i++) {
    await b.mouse.wheel(0, -900); await b.waitForTimeout(250);
  }
  await messageAction(b, message(b, original), 'Reply');
  await send(b, 'Reply to the original');
  await a.bringToFront();
  const reply = message(a, 'Reply to the original').first();
  await reply.waitFor();
  // 답장 말풍선 이름에도 인용된 원문이 들어감: 답장 문구가 없는 원문 말풍선만 봄
  const originalInView = page => page.evaluate(([text, replyText]) => [...document.querySelectorAll('[aria-label]')]
    .filter(e => e.getAttribute('aria-label').includes(text) && !e.getAttribute('aria-label').includes(replyText))
    .some(e => { const r = e.getBoundingClientRect(); return r.height > 0 && r.top >= 0 && r.bottom <= innerHeight; }),
  [original, 'Reply to the original']);
  assert.equal(await originalInView(a), false, 'the original starts out of view');
  const box = await reply.boundingBox();
  await a.mouse.click(box.x + 40, box.y + 18);
  for (let i = 0; i < 15 && !(await originalInView(a)); i++) await a.waitForTimeout(200);
  assert.equal(await originalInView(a), true, 'tapping the quote scrolls to the original');
  await dump(a, 'jumped-to-original');
  await button(a, 'Jump to latest messages').click();
  for (let i = 0; i < 15 && !(await inView(message(a, 'Reply to the original'), 1000)); i++) await a.waitForTimeout(200);
  assert.equal(await inView(message(a, 'Reply to the original'), 1000), true, 'jump to latest returns to the newest message');
  log('tapping a reply quote scrolled to the original message; "Jump to latest" came back');

  // 4. Notifications: content-free while B is in the background.
  await b.bringToFront();
  assert.equal(await b.evaluate(() => Notification.permission), 'granted');
  const focus = await b.context().newCDPSession(b);
  await focus.send('Emulation.setFocusEmulationEnabled', { enabled: false });
  const cover = await b.context().newPage();
  await cover.bringToFront();
  await b.waitForFunction(() => !document.hasFocus());
  await send(a, 'Secret 7731 should not show in a notification');
  await b.waitForFunction(() => window.__igNotes.length > 0, null, { timeout: 15000 });
  const notes = await b.evaluate(() => window.__igNotes);
  assert.deepEqual(notes.at(-1), { title: 'Intragram', body: 'New message' });
  assert.ok(notes.every(n => !JSON.stringify(n).includes('7731')), 'no message content in any notification');
  await b.bringToFront(); await cover.close();
  await focus.send('Emulation.setFocusEmulationEnabled', { enabled: true });
  await focus.detach();
  log('background tab got a content-free notification ("Intragram" / "New message")');

  // 5. Sanitized names and a decompression bomb from B.
  await attach(b, { name: 'invoice\u202Etxt.exe', mimeType: 'application/octet-stream', buffer: Buffer.from('rlo') });
  await a.bringToFront();
  await tile(a, 'invoice').first().waitFor().catch(() => {});
  await dump(a, 'rlo-offered');
  await tile(a, 'invoicetxt.exe').getByRole('button', { name: 'Accept', exact: true }).click();
  assert.deepEqual(await saved(a, 'invoicetxt.exe'), Buffer.from('rlo'));
  assert.ok(!(await a.locator('body').ariaSnapshot()).includes('\u202E'), 'no RLO character reaches the UI');
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(50000, 0); ihdr.writeUInt32BE(50000, 4); ihdr[8] = 8; ihdr[9] = 6;
  const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); return Buffer.concat([len, Buffer.from(type), data, Buffer.alloc(4)]); };
  const bomb = Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', Buffer.alloc(64)), chunk('IEND', Buffer.alloc(0))]);
  await attach(b, { name: 'bomb.png', mimeType: 'image/png', buffer: bomb });
  await a.bringToFront();
  await tile(a, 'bomb.png').getByRole('button', { name: 'Accept', exact: true }).click();
  await tile(a, 'bomb.png').getByRole('button', { name: 'Save to device', exact: true }).waitFor();
  await a.waitForTimeout(1500);
  await dump(a, 'bomb-received');
  log('RLO name shown as invoicetxt.exe; a 50000x50000 PNG arrives as a file without decoding');

  // 5b. A received voice note saved from the browser is a real WAV download (it used to throw: the
  //     save went through the app's folder picker, which does not exist in a browser).
  await b.bringToFront();
  await button(b, 'Tap to record hands-free, or hold to record while pressed').click();
  await button(b, 'Recording. Double tap to send.').waitFor();
  await b.waitForTimeout(1500);
  await button(b, 'Send').last().click();
  await a.bringToFront();
  const voice = a.getByRole('group', { name: /^From .* 0:0\d Encrypted/ }).last();
  await voice.waitFor({ timeout: 25000 });
  const voiceDl = a.waitForEvent('download');
  await voice.getByRole('button', { name: /^Save to device(?: Save to device)?$/ }).click();
  const download = await voiceDl;
  const wav = await readFile(await download.path());
  assert.match(download.suggestedFilename(), /^voice-\d+\.wav$/);
  assert.deepEqual([wav.toString('ascii', 0, 4), wav.toString('ascii', 8, 12), wav.readUInt16LE(20), wav.readUInt16LE(22), wav.readUInt32LE(24), wav.readUInt16LE(34)],
    ['RIFF', 'WAVE', 1, 1, 16000, 16]);
  assert.ok(wav.length > 44 + 16000, 'about a second or more of 16 kHz PCM');
  log(`received voice note saved as ${download.suggestedFilename()} (${wav.length} B, 16 kHz mono PCM16)`);

  // 6. With the peer gone the composer is disabled, so nothing is lost silently. After the peer is
  //    added back with fresh codes, a message too large for "In memory" fails visibly, and Retry
  //    delivers it as message.txt once "As a file" is chosen (same rules as the app).
  await endChat(b);
  await a.bringToFront();
  await a.getByRole('textbox', { name: 'Peer offline', exact: true }).waitFor();
  assert.equal(await composer(a).count(), 0, 'no enabled composer while the peer is offline');
  await link(a, b, { add: true });
  await a.bringToFront();
  await composer(a).waitFor();
  const tooLarge = 'TOO_LARGE_' + 'retry check '.repeat(90000) + '_END';
  assert.ok(Buffer.byteLength(tooLarge) > 1024 * 1024);
  await sendClipText(a, tooLarge);
  // 실패한 긴 말풍선은 버튼으로 읽힘. 이름은 안내와 앞부분, 전송 실패 상태까지만이고 글 전체가 이름이 되지 않음
  const failedBubble = a.getByRole('button', { name: /^From you\s+Long message\.[\s\S]*TOO_LARGE_[\s\S]*failed to send/ });
  await failedBubble.waitFor({ timeout: 60000 });
  const failedName = await failedBubble.evaluate(e => e.textContent);
  assert.ok(failedName.length < 4400 && !failedName.includes('_END'), `bounded accessible name, got ${failedName.length} characters`);
  await dump(a, 'too-large-failed');
  await largeMessages(a, 'As a file');
  // 실패한 말풍선을 활성화하면 다시 보냄 (앱과 같은 동작). 스크린 리더처럼 역할과 이름으로 찾아 활성화함
  await a.bringToFront();
  await failedBubble.evaluate(e => e.click());
  await a.waitForTimeout(1500);
  await dump(a, 'after-retry');
  await b.bringToFront();
  await tile(b, 'message.txt').getByRole('button', { name: 'Accept', exact: true }).click();
  assert.equal((await saved(b, 'message.txt')).toString('utf8'), tooLarge);
  await largeMessages(a, 'In memory');
  log('offline composer is disabled; a too-large message failed visibly and Retry sent it as message.txt');

  // 7. Group member leaves and rejoins the same room with fresh codes.
  const c = await open('C');
  await link(a, c, { add: true });
  await send(c, 'C joined the room');
  await message(b, 'C joined the room').first().waitFor();
  await endChat(c);
  await a.bringToFront();
  await a.waitForTimeout(1500);
  await link(a, c, { add: true });
  await send(c, 'C is back in the room');
  await message(a, 'C is back in the room').first().waitFor();
  await message(b, 'C is back in the room').first().waitFor();
  await send(b, 'B sees C again');
  await message(c, 'B sees C again').first().waitFor();
  await dump(a, 'group-rejoined');
  log('a member who ended the room rejoined with fresh codes; messages flow all ways');

  const external = requests.filter(url => !url.startsWith(origin) && !url.startsWith('blob:') && !url.startsWith('data:'));
  assert.deepEqual(errors, []);
  assert.deepEqual(failedRequests, []);
  assert.deepEqual(external, []);
  log('no runtime errors, no failed or external requests');
  console.log('PASS');
} finally {
  await browser?.close();
  server.close();
}
