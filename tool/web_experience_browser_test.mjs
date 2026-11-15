import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, mkdtemp, mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const root = fileURLToPath(new URL('../docs/', import.meta.url));
const server = createServer(async (req, res) => {
  const pathname = new URL(req.url, 'http://localhost').pathname;
  const file = path.resolve(root, '.' + pathname + (pathname.endsWith('/') ? 'index.html' : ''));
  if (!file.startsWith(root)) { res.writeHead(403).end(); return; }
  try { res.writeHead(200, { 'Content-Type': file.endsWith('.mjs') ? 'text/javascript' : file.endsWith('.css') ? 'text/css' : file.endsWith('.html') ? 'text/html' : 'image/png' }); res.end(await readFile(file)); }
  catch { res.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`, url = origin + '/web/lite.html?lang=ko';
const output = process.env.WEB_QA_OUTPUT_DIR || await mkdtemp(path.join(tmpdir(), 'intragram-experience-'));
await mkdir(output, { recursive: true });
let browser;
try {
  browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH, args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream'] });
  const contexts = await Promise.all([0, 1, 2, 3].map(() => browser.newContext({ viewport: { width: 1440, height: 900 }, permissions: ['microphone'] })));
  const [a, b, c, d] = await Promise.all(contexts.map(context => context.newPage()));
  const errors = [], requests = [];
  for (const page of [a, b, c, d]) { page.on('pageerror', e => errors.push(e.message)); page.on('request', req => requests.push(req.url())); await page.goto(url); }
  const join = async (host, guest, add) => {
    await host.locator(add ? '#add-person' : '#create-offer').click();
    await host.waitForFunction(() => document.getElementById('local-code').value.startsWith('IGW1.'));
    const offer = await host.locator('#local-code').inputValue();
    await guest.locator('#mode-join').click(); await guest.locator('#invite-code').fill(offer); await guest.locator('#accept-offer').click();
    await guest.waitForFunction(() => document.getElementById('local-code').value.startsWith('IGW1.'));
    await host.locator('#answer-code').fill(await guest.locator('#local-code').inputValue()); await host.locator('#accept-answer').click();
    await Promise.all([host.locator('#chat:visible').waitFor(), guest.locator('#chat:visible').waitFor()]);
  };
  const rename = async (page, name) => { await page.locator('#settings-open').click(); await page.locator('#display-name').fill(name); await page.locator('#display-name').press('Tab'); await page.locator('.settings-dialog').getByRole('button', { name: '닫기', exact: true }).click(); };
  const send = async (page, text) => { await page.locator('#message-input').fill(text); await page.locator('#send').click(); };
  await join(a, b, false); await rename(a, 'Host'); await rename(b, 'Bravo');
  await send(b, '첫 대화 보존'); await a.getByText('첫 대화 보존', { exact: true }).waitFor();
  await join(a, c, true); await rename(c, 'Charlie');
  await a.locator('#peer-name').filter({ hasText: '3' }).waitFor();
  await send(b, 'Bravo <script> 그룹 대화');
  await c.getByText('Bravo <script> 그룹 대화', { exact: true }).waitFor();
  assert.equal(await c.locator('#messages script').count(), 0);
  const original = c.locator('.message').filter({ has: c.getByText('Bravo <script> 그룹 대화', { exact: true }) }).first();
  await original.getByRole('button', { name: '답장', exact: true }).click();
  await send(c, 'Charlie의 답장'); await b.getByText('Charlie의 답장', { exact: true }).waitFor();
  await b.locator('.quoted-message').filter({ hasText: 'Bravo <script> 그룹 대화' }).waitFor();
  await original.getByRole('button', { name: '반응', exact: true }).click();
  await original.getByRole('button', { name: '반응 👍', exact: true }).click();
  await b.locator('.reaction-chips').filter({ hasText: '👍' }).waitFor();
  await c.locator('#message-search').fill('does not exist'); assert.equal(await c.locator('.message:visible').count(), 0); await c.locator('#message-search').fill('');
  await b.locator('.message').filter({ has: b.getByText('Bravo <script> 그룹 대화', { exact: true }) }).first().getByRole('button', { name: '모두에게서 삭제', exact: true }).click();
  await c.waitForFunction(() => !document.getElementById('messages').textContent.includes('Bravo <script> 그룹 대화'));
  await a.waitForFunction(() => !document.getElementById('messages').textContent.includes('Bravo <script> 그룹 대화'));
  await a.locator('#burn-ttl').selectOption('5'); await send(a, '5초 뒤 사라질 메시지');
  await c.getByText('5초 뒤 사라질 메시지', { exact: true }).waitFor();
  await c.getByText('5초 뒤 사라질 메시지', { exact: true }).waitFor({ state: 'detached', timeout: 9000 });
  await a.locator('#burn-ttl').selectOption('0');
  await a.locator('#file-peer').selectOption({ label: 'Charlie' });
  assert.equal(await a.locator('#verification-code').innerText(), await c.locator('#verification-code').innerText());
  await a.locator('#verify-peer').click(); await c.locator('#verify-peer').click();
  await a.getByRole('button', { name: '서로 확인 완료', exact: true }).waitFor();
  const payload = Buffer.from('그룹에서 선택한 수신자만 받는 파일\n');
  await a.locator('#file-input').setInputFiles({ name: 'selected.txt', mimeType: 'text/plain', buffer: payload });
  await c.getByRole('button', { name: '받기', exact: true }).click();
  const download = c.waitForEvent('download'); await c.getByRole('link', { name: '파일 저장', exact: true }).click();
  assert.deepEqual(await readFile(await (await download).path()), payload); assert.equal(await b.getByText('selected.txt', { exact: true }).count(), 0);
  await a.locator('#add-person').click(); await a.waitForFunction(() => document.getElementById('local-code').value.startsWith('IGW1.')); await a.locator('#cancel-invite').click(); await a.locator('#chat:visible').waitFor(); await a.getByText('첫 대화 보존', { exact: true }).waitFor();
  await c.locator('#vault-open').click(); await c.locator('#vault-password').fill('private password 123'); await c.locator('#vault-duress').fill('decoy password 123');
  await c.locator('[data-vault-action="vaultSave"]').click(); await c.getByText('대화를 암호화해 보관했습니다.', { exact: true }).waitFor();
  await c.locator('#vault-password').fill('wrong password'); await c.locator('[data-vault-action="vaultUnlock"]').click(); await c.getByText('비밀번호가 다르거나 백업이 손상되었습니다.', { exact: true }).waitFor();
  await c.locator('#vault-password').fill('decoy password 123'); await c.locator('[data-vault-action="vaultUnlock"]').click(); await c.getByText('보관된 대화가 없습니다.', { exact: true }).waitFor(); assert.equal(await c.locator('.vault-view .message').count(), 0);
  await c.locator('#vault-password').fill('private password 123'); await c.locator('[data-vault-action="vaultUnlock"]').click(); await c.locator('.vault-view').getByText('Charlie의 답장', { exact: true }).waitFor();
  const backup = c.waitForEvent('download'); await c.locator('[data-vault-action="vaultBackup"]').click(); const backupBytes = await readFile(await (await backup).path()); assert.ok(!backupBytes.includes(Buffer.from('Charlie의 답장')));
  await c.locator('.vault-dialog').getByRole('button', { name: '닫기', exact: true }).click(); assert.equal(await c.locator('.vault-view .message').count(), 0); assert.equal(await c.locator('#vault-password').inputValue(), '');
  await d.locator('#global-vault').click(); await d.locator('#vault-password').fill('private password 123'); await d.locator('.vault-dialog input[type="file"]').setInputFiles({ name: 'vault.json', mimeType: 'application/json', buffer: backupBytes }); await d.locator('.vault-view').getByText('Charlie의 답장', { exact: true }).waitFor();
  await d.locator('.vault-dialog').getByRole('button', { name: '닫기', exact: true }).click();
  await join(a, d, true); await rename(d, 'Delta'); await send(d, '두 번째 보관 대화');
  await d.locator('#vault-open').click(); await d.locator('#vault-password').fill('private password 123');
  await d.locator('[data-vault-action="vaultSave"]').click(); await d.getByText('대화를 암호화해 보관했습니다.', { exact: true }).waitFor();
  const vaultRecord = page => page.evaluate(() => new Promise((resolve, reject) => {
    const request = indexedDB.open('intragram-web-vault', 1);
    request.onsuccess = () => { const db = request.result, read = db.transaction('vault').objectStore('vault').get('chat'); read.onsuccess = () => { resolve(read.result); db.close(); }; read.onerror = () => reject(read.error); };
  }));
  const savedRecord = await vaultRecord(d);
  await d.locator('#vault-password').fill('wrong password'); await d.locator('[data-vault-action="vaultSave"]').click();
  await d.getByText('비밀번호가 다르거나 백업이 손상되었습니다.', { exact: true }).waitFor(); assert.deepEqual(await vaultRecord(d), savedRecord, 'a wrong password must not overwrite old archives');
  await d.locator('#vault-password').fill('private password 123'); await d.locator('[data-vault-action="vaultUnlock"]').click();
  await d.waitForFunction(() => document.getElementById('vault-conversations').options.length === 2);
  await d.locator('#vault-conversations').selectOption('0'); await d.locator('.vault-view').getByText('Charlie의 답장', { exact: true }).waitFor();
  await d.locator('#vault-conversations').selectOption('1'); await d.locator('.vault-view').getByText('두 번째 보관 대화', { exact: true }).waitFor();
  // A cancelled slow unlock cannot repopulate plaintext after the lock handler.
  await d.evaluate(() => {
    const original = crypto.subtle.decrypt.bind(crypto.subtle); window.qaDecryptEntered = false; window.qaDecryptFinished = false;
    crypto.subtle.decrypt = async (...args) => { window.qaDecryptEntered = true; await new Promise(resolve => window.qaReleaseDecrypt = resolve); try { return await original(...args); } finally { window.qaDecryptFinished = true; crypto.subtle.decrypt = original; } };
  });
  await d.locator('#vault-password').fill('private password 123'); await d.locator('[data-vault-action="vaultUnlock"]').click();
  await d.waitForFunction(() => window.qaDecryptEntered); await d.keyboard.press('Escape');
  await d.evaluate(() => window.qaReleaseDecrypt()); await d.waitForFunction(() => window.qaDecryptFinished);
  assert.equal(await d.locator('.vault-view .message').count(), 0); assert.equal(await d.locator('#vault-password').inputValue(), '');
  // File batches keep recipient choice and wait for each consent/receipt.
  await a.locator('#file-peer').selectOption({ label: 'Charlie' });
  await a.locator('#file-input').setInputFiles([
    { name: 'batch-one.txt', mimeType: 'text/plain', buffer: Buffer.from('one') },
    { name: 'batch-two.txt', mimeType: 'text/plain', buffer: Buffer.from('two') },
  ]);
  for (const name of ['batch-one.txt', 'batch-two.txt']) {
    const tile = c.locator('.transfer').filter({ has: c.getByText(name, { exact: true }) });
    await tile.getByRole('button', { name: '받기', exact: true }).click(); await tile.getByRole('link', { name: '파일 저장', exact: true }).waitFor();
  }
  assert.equal(await b.getByText('batch-one.txt', { exact: true }).count(), 0);
  // Inspect a real signed file receipt and exchange its Merkle proof/witness through the UI.
  await a.locator('#evidence-open').click(); await a.locator('#evidence-peer').selectOption({ label: 'Charlie' });
  await a.locator('#evidence-list').getByText('서명·연결·내용 확인', { exact: true }).first().waitFor();
  const evidenceDownload = a.waitForEvent('download'); await a.locator('[data-evidence-action="evidenceExport"]').click();
  const evidenceBytes = await readFile(await (await evidenceDownload).path());
  await c.locator('#evidence-open').click(); await c.locator('[data-evidence-action="evidenceVerify"]').click();
  await c.locator('.evidence-dialog input[type="file"]').setInputFiles({ name: 'audit.json', mimeType: 'application/json', buffer: evidenceBytes });
  await c.getByText('서명과 Merkle 포함 증명이 유효합니다.', { exact: true }).waitFor();
  const forgedEvidence = JSON.parse(evidenceBytes); forgedEvidence.entries[0].attestation.o = 'forged';
  await c.locator('[data-evidence-action="evidenceVerify"]').click(); await c.locator('.evidence-dialog input[type="file"]').setInputFiles({ name: 'forged.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(forgedEvidence)) });
  await c.getByText('증적 또는 자격 파일이 올바르지 않습니다. 서명·연결·내용을 확인하지 못했습니다.', { exact: true }).waitFor();
  const witnessDownload = c.waitForEvent('download'); await c.locator('[data-evidence-action="evidenceWitness"]').click();
  await c.locator('.evidence-dialog input[type="file"]').setInputFiles({ name: 'audit.json', mimeType: 'application/json', buffer: evidenceBytes });
  const witnessBytes = await readFile(await (await witnessDownload).path());
  await a.locator('[data-evidence-action="evidenceAttachAnchor"]').click(); await a.locator('.evidence-dialog input[type="file"]').setInputFiles({ name: 'anchor.json', mimeType: 'application/json', buffer: witnessBytes });
  await a.getByText('상대의 증인 영수증을 붙였습니다. 다시 내보내면 포함됩니다.', { exact: true }).waitFor();
  await a.locator('.evidence-dialog').getByRole('button', { name: '닫기', exact: true }).click(); await c.locator('.evidence-dialog').getByRole('button', { name: '닫기', exact: true }).click();
  await c.locator('#voice').click(); await c.locator('.voice-dialog').getByRole('button', { name: '녹음 종료', exact: true }).waitFor();
  await c.waitForTimeout(600); await c.locator('.voice-dialog').getByRole('button', { name: '녹음 종료', exact: true }).click();
  await c.locator('.voice-dialog audio:visible').waitFor(); await c.locator('.voice-dialog').getByRole('button', { name: '보내기', exact: true }).click();
  await a.getByRole('button', { name: '받기', exact: true }).click(); await a.locator('.transfer audio').waitFor();
  assert.equal(await c.evaluate(() => document.querySelector('.voice-dialog').open), false);
  for (const width of [390, 768, 1440]) { await c.setViewportSize({ width, height: 844 }); assert.ok(await c.evaluate(() => document.documentElement.scrollWidth <= innerWidth)); const box = await c.locator('#send').boundingBox(); assert.ok(box.y + box.height <= 844); }
  await c.locator('#theme').selectOption('light'); await c.screenshot({ path: path.join(output, 'group-light-1440.png'), fullPage: true });
  await c.setViewportSize({ width: 390, height: 844 }); await c.locator('#theme').selectOption('dark'); await c.screenshot({ path: path.join(output, 'group-dark-390.png'), fullPage: true });
  // Full panic clears every same-profile tab, saved vault and application identity.
  const sibling = await contexts[3].newPage(); await sibling.goto(url); await sibling.locator('#global-evidence').click();
  await sibling.waitForFunction(() => document.getElementById('evidence-identity').textContent.split('\n')[0].includes(': ') && !document.getElementById('evidence-identity').textContent.split('\n')[0].endsWith('—'));
  const oldIdentity = await sibling.locator('#evidence-identity').innerText(); await sibling.locator('.evidence-dialog').getByRole('button', { name: '닫기', exact: true }).click();
  await d.locator('#settings-open').click(); await d.locator('#panic-all').click(); await d.locator('#panic-confirm').click();
  await d.waitForFunction(() => document.getElementById('connection-status').dataset.state === 'idle');
  await d.waitForFunction(() => new Promise(resolve => { const open = indexedDB.open('intragram-web-vault', 1); open.onsuccess = () => { const db = open.result, read = db.transaction('vault').objectStore('vault').get('chat'); read.onsuccess = () => { resolve(!read.result); db.close(); }; }; }));
  await sibling.locator('#global-vault').click(); await sibling.locator('#vault-password').fill('private password 123'); await sibling.locator('[data-vault-action="vaultUnlock"]').click();
  await sibling.getByText('이 브라우저에 보관한 대화가 없습니다.', { exact: true }).waitFor(); assert.equal(await vaultRecord(d), undefined);
  await sibling.locator('.vault-dialog').getByRole('button', { name: '닫기', exact: true }).click(); await sibling.locator('#global-evidence').click();
  assert.notEqual(await sibling.locator('#evidence-identity').innerText(), oldIdentity, 'panic rotates the shared application identity');
  assert.equal(await d.locator('#messages .message,.transfer').count(), 0); assert.equal(await d.locator('.evidence-list li').count(), 0);
  assert.deepEqual(errors, []); assert.ok(requests.every(request => request.startsWith(origin + '/') || request.startsWith('blob:')));
  console.log('PASS: encrypted host room; reply/reaction/read/burn/search; recipient-specific batches; per-link verification; preserved multi-chat vault, wrong-password overwrite rejection, cancelled unlock lock, decoy backup/import; signed receipt/Merkle/witness UI; WAV voice recording/playback; responsive composer; full same-profile panic and identity rotation; no external requests. Screenshots: ' + output);
} finally { await browser?.close(); await new Promise(resolve => server.close(resolve)); }
