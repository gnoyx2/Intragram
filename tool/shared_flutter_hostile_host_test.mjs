// Shared Flutter web, hostile room host: the host page runs the real app, but everything it sends
// passes through a wire hook that alters, strips, replays or invents frames about another member.
// An unmodified Flutter member must refuse them and show the room integrity warning.
// The hook lives only in this QA script (RTCDataChannel.prototype.send of the host page).
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const root = path.resolve(process.env.SHARED_WEB_BUILD_DIR || fileURLToPath(new URL('../build/web/', import.meta.url)));
const output = process.env.WEB_QA_OUTPUT_DIR || await mkdtemp(path.join(tmpdir(), 'intragram-hostile-host-'));
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
const errors = [];
const log = msg => console.log('hostile host QA: ' + msg);
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
const status = (page, text) => page.getByText(text, { exact: true }).or(page.getByLabel(text, { exact: true })).first();
const VERIFIED = 'Observed author signatures verified · checkpoints observed';
const CONFLICT = 'Conflict Detected · room integrity warning';

// 호스트 페이지에만 넣는 전송 가로채기: 다른 멤버가 쓴 서명 메시지를 중계할 때 mode대로 바꿈
function wireHook() {
  const real = RTCDataChannel.prototype.send;
  const relayed = new Map(); // 본문 → { channel, control }
  const state = window.__hostile = { mode: 'off', forged: 'FORGED BY HOST', done: [], hostSlot: null };
  const fresh = () => [...crypto.getRandomValues(new Uint8Array(16))].map(b => b.toString(16).padStart(2, '0')).join('');
  const put = (channel, control) => real.call(channel, JSON.stringify({ kind: 'control', id: fresh(), control }));
  state.replay = text => { const r = relayed.get(text); put(r.channel, r.control); };
  state.inject = (text, make) => { const r = relayed.get(text); put(r.channel, make(r.control, state.hostSlot)); };
  state.known = text => relayed.has(text);
  RTCDataChannel.prototype.send = function (data) {
    if (typeof data !== 'string') return real.call(this, data);
    let frame;
    try { frame = JSON.parse(data); } catch { return real.call(this, data); }
    const c = frame.kind === 'control' ? frame.control : null;
    if (c?.k === 'room-state') state.hostSlot = c.host;
    const other = c?.k === 'native-room' && c.frame?.k === 'msg' && c.frame.authorPeerId !== c.host;
    if (!other) return real.call(this, data);
    relayed.set(c.frame.text, { channel: this, control: structuredClone(c) });
    if (state.mode === 'tamper') {
      state.done.push('tamper');
      return put(this, { ...c, frame: { ...c.frame, text: state.forged } });
    }
    if (state.mode === 'strip') {
      state.done.push('strip');
      return put(this, { k: 'room-msg', id: c.frame.id, origin: c.origin, alias: c.alias, text: c.frame.text });
    }
    return real.call(this, data);
  };
}

async function open(name, { hostile = false } = {}) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, locale: 'en-US', permissions: ['clipboard-read', 'clipboard-write'] });
  if (hostile) await context.addInitScript(wireHook);
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
// 호스트 H(가로채기 있음)와 멤버 A·B의 방. 세 사람이 서명 글을 한 번씩 보내 A가 B의 서명을 관측한 상태로 돌려줌
async function room(tag) {
  const h = await open('H' + tag, { hostile: true }), a = await open('A' + tag), b = await open('B' + tag);
  await link(h, a);
  await a.bringToFront();
  await composer(a).waitFor();
  await link(h, b, { add: true });
  await h.bringToFront();
  await h.getByRole('heading', { name: /you host · 3 people/ }).waitFor();
  await send(h, `${tag} host hello`);
  await send(a, `${tag} A hello`);
  await send(b, `${tag} B hello`);
  await a.bringToFront();
  await message(a, `${tag} B hello`).first().waitFor();
  await message(a, `${tag} host hello`).first().waitFor();
  await status(a, VERIFIED).waitFor();
  assert.equal(await status(a, CONFLICT).count(), 0);
  return { h, a, b };
}
const mode = (h, value) => h.evaluate(v => { window.__hostile.mode = v; }, value);
const done = h => h.evaluate(() => window.__hostile.done);
const close = pages => Promise.all(Object.values(pages).map(p => p.context().close()));

try {
  browser = await chromium.launch({ executablePath: process.env.CHROME_PATH, headless: true });

  // 1. The host changes the text of another member's signed message.
  {
    const r = await room('T');
    await mode(r.h, 'tamper');
    await send(r.b, 'T B original text');
    await r.a.bringToFront();
    await status(r.a, CONFLICT).waitFor();
    assert.deepEqual(await done(r.h), ['tamper']);
    assert.equal(await message(r.a, 'FORGED BY HOST').count(), 0, 'the altered text is never shown');
    assert.equal(await message(r.a, 'T B original text').count(), 0);
    assert.equal(await message(r.a, 'T B hello').count(), 1, 'earlier messages stay');
    await dump(r.a, 'tampered-text');
    log('altered text of a signed message: not shown, the member shows "' + CONFLICT + '"');
    await close(r);
  }

  // 2. The host strips the signature and passes the message on as an unsigned one.
  {
    const r = await room('S');
    await mode(r.h, 'strip');
    await send(r.b, 'S B stripped message');
    await r.a.bringToFront();
    await status(r.a, CONFLICT).waitFor();
    assert.deepEqual(await done(r.h), ['strip']);
    assert.equal(await message(r.a, 'S B stripped message').count(), 0, 'an unsigned message from a signing author is never shown');
    await dump(r.a, 'stripped-signature');
    log('signature stripped from a signing author: not shown, the member shows "' + CONFLICT + '"');
    await close(r);
  }

  // 3. Replays and invented controls about another member's signed message.
  {
    const r = await room('R');
    await send(r.b, 'R B stays');
    await send(r.b, 'R B deleted here');
    await r.a.bringToFront();
    await message(r.a, 'R B deleted here').first().waitFor();
    await message(r.a, 'R B stays').first().waitFor();
    assert.ok(await r.h.evaluate(() => window.__hostile.known('R B stays') && window.__hostile.known('R B deleted here')));
    await message(r.a, 'R B deleted here').first().click({ button: 'right', force: true });
    await r.a.getByText('Delete for me', { exact: true }).click();
    await message(r.a, 'R B deleted here').waitFor({ state: 'detached' });

    // 서명된 프레임을 그대로 다시 보냄: 지운 글이 되살아나지 않고 남은 글도 겹치지 않음
    await r.h.evaluate(() => { window.__hostile.replay('R B deleted here'); window.__hostile.replay('R B stays'); });
    await r.a.waitForTimeout(2500);
    assert.equal(await message(r.a, 'R B deleted here').count(), 0, 'a replayed signed frame does not bring a deleted message back');
    assert.equal(await message(r.a, 'R B stays').count(), 1, 'a replayed signed frame is not shown twice');
    log('replayed signed frames: the deleted message stays deleted, nothing is duplicated');

    // 서명 글의 타이머를 작성자 이름으로 바꾸려 함: 적용되지 않음 (적용됐다면 읽은 뒤 5초에 사라짐)
    await r.h.evaluate(() => window.__hostile.inject('R B stays', c => ({ k: 'room-control', origin: c.origin, control: { k: 'meta', id: c.frame.id, ttl: 5 } })));
    await r.a.waitForTimeout(9000);
    assert.equal(await message(r.a, 'R B stays').count(), 1, 'an invented timer does not burn a signed message');
    log('invented burn timer for a signed message: ignored');

    // 작성자가 아닌 자리(호스트 자신) 이름으로 소각을 보냄: 거절
    await r.h.evaluate(() => window.__hostile.inject('R B stays', (c, hostSlot) => ({ k: 'room-control', origin: hostSlot, control: { k: 'burn', id: c.frame.id } })));
    await r.a.waitForTimeout(2500);
    assert.equal(await message(r.a, 'R B stays').count(), 1, 'a burn in another origin\'s name is refused');
    assert.equal(await status(r.a, CONFLICT).count(), 0);
    await status(r.a, VERIFIED).waitFor();
    log('burn sent in the host\'s own name for a member\'s message: refused');

    // 알려진 한계: 소각은 서명되지 않아 호스트가 작성자 자리 이름으로 보내면 적용됨 (SECURITY.md에 적힌 범위)
    await r.h.evaluate(() => window.__hostile.inject('R B stays', c => ({ k: 'room-control', origin: c.origin, control: { k: 'burn', id: c.frame.id } })));
    await message(r.a, 'R B stays').waitFor({ state: 'detached' });
    await dump(r.a, 'forged-burn-applied');
    log('KNOWN LIMIT: a burn the host sends in the author\'s name removes the message (burns are not signed)');
    await close(r);
  }

  assert.deepEqual(errors, []);
  console.log('PASS: hostile host checks complete. Artifacts: ' + output);
} catch (error) {
  console.error('hostile host QA failure artifacts: ' + output + '\nErrors: ' + JSON.stringify(errors));
  throw error;
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
}
