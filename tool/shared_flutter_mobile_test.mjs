// Phone browsers: the shared Flutter UI in iPhone- and Android-emulated Chromium against a desktop
// Chromium peer. The phone scans the desktop's invitation QR with a fake camera that plays that QR,
// then chats, long-presses a message, saves a received photo through the share sheet, and is asked
// before the back gesture leaves the page. Set WEB_APP_URL to the app page (local preview or deployed).
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const app = process.env.WEB_APP_URL || 'http://127.0.0.1:8765/web/app/';
const output = process.env.WEB_QA_OUTPUT_DIR || await mkdtemp(path.join(tmpdir(), 'intragram-mobile-web-'));
await mkdir(output, { recursive: true });
const phones = {
  ios: { viewport: { width: 393, height: 659 }, screen: { width: 393, height: 852 }, deviceScaleFactor: 3, platform: 'iPhone', vibrate: false,
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Mobile/15E148 Safari/604.1' },
  android: { viewport: { width: 412, height: 839 }, screen: { width: 412, height: 915 }, deviceScaleFactor: 2.625, platform: 'Linux armv8l', vibrate: true,
    userAgent: 'Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Mobile Safari/537.36' },
};
const errors = [];
const browsers = [];
let phonePage;
const watch = (page, name) => {
  page.setDefaultTimeout(20000);
  page.on('pageerror', e => errors.push(`${name}: ${e.message}`));
  page.on('console', m => { if (m.type() === 'error') errors.push(`${name}: ${m.text()}`); });
};
const open = async (page, touch) => {
  await page.goto(app + '?lang=en');
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached' });
  await page.locator('#app-loading').waitFor({ state: 'detached', timeout: 30000 });
  const box = await page.locator('flt-semantics-placeholder').boundingBox();
  if (touch) await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  else await page.locator('flt-semantics-placeholder').evaluate(e => e.click());
  await page.getByRole('heading', { name: /^Intragram/ }).waitFor();
};
const button = (page, name) => page.getByRole('button', { name, exact: true });
const tap = (page, locator) => page.context()._touch ? locator.tap() : locator.click();
const fill = async (page, field, value) => {
  await tap(page, field);
  await page.waitForTimeout(150);
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.insertText(value);
  await page.waitForTimeout(100);
};
const copied = async page => { await tap(page, button(page, 'Copy code')); return page.evaluate(() => navigator.clipboard.readText()); };
const shot = (page, name) => page.screenshot({ path: path.join(output, name + '.png') });
// Touch drag on the Flutter view (Playwright has no swipe for touch contexts).
const swipeUp = page => page.evaluate(async () => {
  const view = document.querySelector('flutter-view');
  const x = innerWidth / 2, from = innerHeight * 0.75, to = innerHeight * 0.3;
  const at = (y, buttons) => ({ pointerId: 42, pointerType: 'touch', isPrimary: true, clientX: x, clientY: y, buttons, button: 0, bubbles: true, cancelable: true, composed: true });
  view.dispatchEvent(new PointerEvent('pointerdown', at(from, 1)));
  for (let i = 1; i <= 10; i++) { await new Promise(r => setTimeout(r, 16)); view.dispatchEvent(new PointerEvent('pointermove', at(from + (to - from) * i / 10, 1))); }
  view.dispatchEvent(new PointerEvent('pointerup', at(to, 0)));
  await new Promise(r => setTimeout(r, 400));
});

// The desktop shows its invitation QR; that QR becomes the phone's camera picture (Y4M, 1920x1080).
async function invitationCamera(desk, file) {
  await desk.getByRole('button', { name: 'Show QR code', exact: true }).click();
  const qr = desk.getByText('qr code', { exact: true });
  await qr.waitFor();
  // Wait out the dialog animation, and keep a white margin: the QR's own box clips its quiet zone.
  await desk.waitForTimeout(800);
  const box = await qr.boundingBox();
  const png = (await desk.screenshot({ clip: { x: box.x - 24, y: box.y - 24, width: box.width + 48, height: box.height + 48 } })).toString('base64');
  await desk.keyboard.press('Escape');
  const W = 1920, H = 1080;
  const luma = Buffer.from(await desk.evaluate(async ({ png, W, H }) => {
    const bitmap = await createImageBitmap(new Blob([Uint8Array.from(atob(png), c => c.charCodeAt(0))], { type: 'image/png' }));
    const canvas = new OffscreenCanvas(W, H), g = canvas.getContext('2d');
    g.fillStyle = '#fff'; g.fillRect(0, 0, W, H);
    g.drawImage(bitmap, (W - 820) / 2, (H - 820) / 2, 820, 820);
    const { data } = g.getImageData(0, 0, W, H);
    let s = '';
    for (let i = 0; i < W * H; i++) s += String.fromCharCode((data[i * 4] * 77 + data[i * 4 + 1] * 150 + data[i * 4 + 2] * 29) >> 8);
    return btoa(s);
  }, { png, W, H }), 'base64');
  const chroma = Buffer.alloc(W * H / 2, 128);
  await writeFile(file, Buffer.concat([Buffer.from(`YUV4MPEG2 W${W} H${H} F10:1 Ip A1:1 C420jpeg\nFRAME\n`), luma, chroma]));
}

async function run(kind) {
  const phone = phones[kind];
  const deskBrowser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH });
  browsers.push(deskBrowser);
  const deskContext = await deskBrowser.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 3, locale: 'en-US', permissions: ['clipboard-read', 'clipboard-write'] });
  const desk = await deskContext.newPage();
  watch(desk, `${kind} desktop`);
  await open(desk, false);
  await button(desk, 'Encrypted app–web connection').first().click();
  await button(desk, 'Create invitation code').click();
  await desk.getByRole('textbox', { name: 'Your connection code', exact: true }).waitFor();
  const offer = await copied(desk);
  const camera = path.join(output, `${kind}-invitation.y4m`);
  await invitationCamera(desk, camera);

  const phoneBrowser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH,
    args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream', `--use-file-for-fake-video-capture=${camera}`] });
  browsers.push(phoneBrowser);
  const { platform, vibrate, ...device } = phone;
  const phoneContext = await phoneBrowser.newContext({ ...device, isMobile: true, hasTouch: true, locale: 'en-US', permissions: ['clipboard-read', 'clipboard-write', 'camera'] });
  phoneContext._touch = true;
  await phoneContext.addInitScript(({ platform, vibrate }) => {
    Object.defineProperty(Navigator.prototype, 'platform', { get: () => platform });
    Object.defineProperty(Navigator.prototype, 'maxTouchPoints', { get: () => 5 });
    // Share sheet stand-in records what the page shares; iOS Safari has no vibration API.
    window.__shared = []; window.__vibrations = [];
    Object.defineProperty(Navigator.prototype, 'canShare', { configurable: true, value: data => !!data?.files?.length });
    Object.defineProperty(Navigator.prototype, 'share', { configurable: true, value: async data => {
      for (const f of data.files) window.__shared.push({ name: f.name, type: f.type, size: f.size, head: [...new Uint8Array(await f.slice(0, 8).arrayBuffer())] });
    } });
    if (vibrate) Object.defineProperty(Navigator.prototype, 'vibrate', { configurable: true, value: p => { window.__vibrations.push(p); return true; } });
    else delete Navigator.prototype.vibrate;
  }, { platform, vibrate });
  const mob = await phoneContext.newPage();
  phonePage = { kind, page: mob };
  watch(mob, `${kind} phone`);
  await open(mob, true);
  const theme = await mob.evaluate(() => document.querySelector('meta[name="theme-color"]')?.content?.toLowerCase());
  assert.ok(theme && theme !== '#2563eb', `browser bar follows the app bar, got ${theme}`);
  await shot(mob, `${kind}-home`);

  // Camera scan: the invitation goes straight into the join dialog.
  await tap(mob, button(mob, 'Scan an invitation code').first());
  await mob.getByRole('heading', { name: 'Scan an invitation code' }).waitFor();
  const field = mob.getByRole('textbox', { name: 'Their invitation code', exact: true });
  await field.waitFor({ timeout: 30000 });
  // The field shows the scanned code; the connection below only opens with the exact invitation.
  await shot(mob, `${kind}-scanned`);
  console.log(`${kind}: camera scan read the desktop invitation QR`);
  await tap(mob, button(mob, 'Create response code'));
  await mob.getByRole('textbox', { name: 'Your connection code', exact: true }).waitFor();
  const answer = await copied(mob);
  await tap(mob, button(mob, 'Open conversation'));
  await fill(desk, desk.getByRole('textbox', { name: 'Their response code', exact: true }), answer);
  await desk.evaluate(() => document.activeElement?.blur());
  await button(desk, 'Connect').click();
  for (const page of [desk, mob]) await page.getByRole('textbox', { name: 'Message', exact: true }).waitFor();

  await fill(desk, desk.getByRole('textbox', { name: 'Message', exact: true }), 'Hello phone');
  await desk.keyboard.press('Enter');
  const bubble = mob.getByRole('button', { name: /Hello phone/ }).first();
  await bubble.waitFor();
  await mob.waitForTimeout(400);
  const buzzed = await mob.evaluate(() => window.__vibrations.length);
  if (vibrate) assert.ok(buzzed > 0, 'Android browser vibrates for a message in the open app like the app');
  await fill(mob, mob.getByRole('textbox', { name: 'Message', exact: true }), 'Hello desktop');
  await tap(mob, button(mob, 'Send'));
  await desk.getByText(/Hello desktop/).first().waitFor();

  // Long press opens the same message actions as the app (touch pointer held past the long-press delay).
  const b = await bubble.boundingBox();
  await mob.evaluate(async ({ x, y }) => {
    const view = document.querySelector('flutter-view');
    const touch = { pointerId: 41, pointerType: 'touch', isPrimary: true, clientX: x, clientY: y, bubbles: true, cancelable: true, composed: true };
    view.dispatchEvent(new PointerEvent('pointerdown', { ...touch, button: 0, buttons: 1, pressure: 0.5 }));
    await new Promise(r => setTimeout(r, 900));
    view.dispatchEvent(new PointerEvent('pointerup', { ...touch, button: 0, buttons: 0 }));
  }, { x: b.x + b.width / 2, y: b.y + b.height / 2 });
  await mob.getByText('Reply', { exact: true }).waitFor();
  await shot(mob, `${kind}-message-actions`);
  await mob.keyboard.press('Escape');
  await mob.getByText('Reply', { exact: true }).waitFor({ state: 'detached' });

  // A received photo is kept through the share sheet (Save Image, Files, other apps).
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGP8z8Dwn4GBgYGJgQEAKQoCAh0q+IoAAAAASUVORK5CYII=', 'base64');
  const chooser = desk.waitForEvent('filechooser');
  await button(desk, 'Send a file').first().click();
  await (await chooser).setFiles([{ name: 'photo.png', mimeType: 'image/png', buffer: png }]);
  await tap(mob, mob.getByRole('button', { name: /^Accept/ }).first());
  const save = button(mob, 'Share or save');
  await save.waitFor();
  await tap(mob, save);
  await mob.waitForFunction(() => window.__shared.length === 1);
  const [shared] = await mob.evaluate(() => window.__shared);
  assert.deepEqual(shared, { name: 'photo.png', type: 'image/png', size: png.length, head: [...png.subarray(0, 8)] });
  console.log(`${kind}: received photo handed to the share sheet byte-exact`);

  // With chats open, a reload, tab close or address change asks first (the browser skips the in-app
  // question when Back is pressed twice without touching the page).
  assert.equal(await mob.evaluate(() => { const e = new Event('beforeunload', { cancelable: true }); dispatchEvent(e); return e.defaultPrevented; }), true);
  // The back gesture first closes the open chat without asking, then on Home asks before leaving
  // the page and its chats.
  await mob.waitForTimeout(600);
  await mob.evaluate(() => history.back());
  await mob.getByRole('heading', { name: /^Intragram/ }).waitFor();
  await mob.waitForTimeout(600);
  assert.equal(await mob.getByText('Leave this page?').count(), 0, 'back from a chat only closes the chat');
  await mob.evaluate(() => history.back());
  await mob.getByText('Leave this page?').waitFor();
  await shot(mob, `${kind}-leave-guard`);
  await tap(mob, button(mob, 'Stay'));
  await mob.getByText('Leave this page?').waitFor({ state: 'detached' });
  assert.match(mob.url(), /\/web\/app\//);

  // Settings: no page notifications phones cannot show, and the background limit is stated.
  await tap(mob, button(mob, 'More').first());
  await tap(mob, mob.getByRole('menuitem', { name: 'Settings', exact: true }));
  await mob.getByRole('heading', { name: 'Settings', exact: true }).waitFor();
  // The note sits in the Connection section, which names itself with its rows.
  const note = mob.getByRole('banner', { name: /Phone browsers pause this page/ });
  for (let i = 0; i < 10 && !(await note.count()); i++) await swipeUp(mob);
  await note.waitFor();
  assert.equal(await mob.getByRole('button', { name: /Allow browser notifications/ }).count(), 0);
  await shot(mob, `${kind}-settings`);
  console.log(`${kind}: back guard, settings and theme color (${theme}) match the app`);
  await phoneBrowser.close();
  await deskBrowser.close();
}

try {
  for (const kind of Object.keys(phones)) await run(kind);
  assert.deepEqual(errors, []);
  console.log('Mobile web parity QA PASS:', output);
} catch (error) {
  // Leave the phone screen and its accessibility tree next to the screenshots.
  if (phonePage) {
    await shot(phonePage.page, `${phonePage.kind}-failure`).catch(() => {});
    await writeFile(path.join(output, `${phonePage.kind}-failure.txt`), await phonePage.page.locator('body').ariaSnapshot().catch(String));
  }
  throw error;
} finally {
  for (const browser of browsers) await browser.close().catch(() => {});
}
