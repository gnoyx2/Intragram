// Run against tool/web_peer_harness.dart, a separate QA-only Flutter entry point.
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const port = process.env.QA_PORT || JSON.parse(await readFile(process.env.QA_STATUS_FILE, 'utf8')).port;
const api = async (route, data = {}) => {
  const response = await fetch(`http://127.0.0.1:${port}${route}`, {
    method: 'POST', headers: { 'x-qa-secret': process.env.QA_SECRET }, body: JSON.stringify(data),
  });
  const value = await response.json();
  assert.equal(response.status, 200, JSON.stringify(value)); return value;
};
const until = async (predicate, timeout = 20000) => {
  const end = Date.now() + timeout;
  while (!await predicate()) {
    if (Date.now() > end) throw Error('Native/browser condition timed out');
    await new Promise(resolve => setTimeout(resolve, 50));
  }
};
const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH });
const page = await browser.newPage();
const requests = [];
page.on('request', request => requests.push(request.url()));
try {
  await page.goto(process.env.WEB_PREVIEW_URL || 'http://127.0.0.1:8765/web/lite.html?lang=ko');
  const initBrowser = () => page.evaluate(async () => {
    await window.qaPeer?.close();
    const { PeerSession } = await import('./peer.mjs');
    const { WebPeerEvidence } = await import('./evidence.mjs');
    window.qa = { state: 'idle', messages: [], controls: [], transfers: {}, errors: [] };
    window.qaEvidenceReady = Promise.resolve();
    window.qaEvidence = new WebPeerEvidence({ sendControl: control => window.qaPeer.sendControl(control) });
    window.qaPeer = new PeerSession({
      onState: state => {
        window.qa.state = state;
        if (state === 'connected') window.qaEvidenceReady = window.qaEvidence.start(window.qaPeer.sessionBinding,
          { dialled: window.qaPeer.pc.localDescription.type === 'offer' });
      },
      onMessage: value => window.qa.messages.push(value),
      onControl: value => {
        window.qa.controls.push(value);
        window.qaEvidenceReady.then(() => window.qaEvidence.receive(value)).catch(e => window.qa.errors.push(e.message));
      },
      onTransfer: value => {
        window.qa.transfers[value.id] = value;
        if (value.blob) value.blob.arrayBuffer().then(buffer => window.qaEvidenceReady.then(() =>
          window.qaEvidence.recordFile(value.id, new Uint8Array(buffer)))).catch(e => window.qa.errors.push(e.message));
      },
      onError: value => window.qa.errors.push(value.code || value.message),
    });
  });
  const connected = async () => {
    await until(async () => (await api('/state')).state === 'connected' &&
      await page.evaluate(() => window.qa.state === 'connected'));
    assert.equal((await api('/state')).sas, await page.evaluate(() => window.qaPeer.verificationCode));
  };
  await api('/reset'); await initBrowser();
  const offer = await api('/create');
  const answer = await page.evaluate(code => window.qaPeer.acceptOffer(code), offer.code);
  await api('/answer', { code: answer }); await connected();
  await until(async () => (await api('/state')).peerIdentity &&
    await page.evaluate(() => !!window.qaEvidence.peerIdentity));

  const nativeText = 'native → web encrypted 한글 <script>test</script>';
  await api('/text', { text: nativeText });
  await until(() => page.evaluate(text => window.qa.messages.some(message => message.text === text), nativeText));
  await page.evaluate(() => window.qaPeer.sendText('web → native encrypted 한글'));
  await until(async () => (await api('/state')).messages.includes('web → native encrypted 한글'));
  await api('/control', { control: { k: 'rename', alias: 'Native QA' } });
  await until(() => page.evaluate(() => window.qa.controls.some(c => c.k === 'rename' && c.alias === 'Native QA')));
  await page.evaluate(() => window.qaPeer.sendControl({ k: 'typing', on: true }));
  await until(async () => (await api('/state')).controls.some(c => c.k === 'typing' && c.on));
  const payload = Buffer.alloc(256 * 1024 + 37);
  for (let i = 0; i < payload.length; i++) payload[i] = i % 251;
  const outbound = await api('/file', { name: 'native-한글.bin', bytes: payload.toString('base64') });
  await until(() => page.evaluate(id => window.qa.transfers[id]?.state === 'offered', outbound.id));
  await page.evaluate(id => window.qaPeer.acceptFile(id), outbound.id);
  await until(() => page.evaluate(id => window.qa.transfers[id]?.state === 'complete', outbound.id));
  const received = await page.evaluate(async id => Array.from(new Uint8Array(await window.qa.transfers[id].blob.arrayBuffer())), outbound.id);
  assert.deepEqual(Buffer.from(received), payload);
  await until(async () => (await api('/state')).transfers.find(value => value.id === outbound.id)?.state === 'complete');
  await until(async () => (await api('/state')).proofs.some(value => value.id === outbound.id && value.status === 'verified'));
  const nativeBundle = (await api('/proof-export')).bundle;
  assert.equal(await page.evaluate(bundle => window.qaEvidence.importBundle(bundle), nativeBundle), true);

  const inboundId = await page.evaluate(async bytes => {
    const body = Uint8Array.from(bytes), id = window.qaPeer.offerFile(new File([body], 'browser.bin'));
    await window.qaEvidence.expectFile(id, body); return id;
  }, [...payload]);
  await until(async () => (await api('/state')).transfers.some(value => value.id === inboundId));
  await api('/accept', { id: inboundId });
  await until(async () => (await api('/state')).transfers.find(value => value.id === inboundId)?.state === 'complete');
  assert.deepEqual(Buffer.from((await api('/state')).transfers.find(value => value.id === inboundId).bytes, 'base64'), payload);
  await until(() => page.evaluate(id => window.qaEvidence.entries.some(e => e.attestation.s === id && e.status === 'verified'), inboundId));
  const webBundle = await page.evaluate(() => window.qaEvidence.exportBundle());
  assert.equal((await api('/proof-import', { bundle: webBundle })).valid, true);

  const empty = await api('/file', { name: 'empty.txt', bytes: '' });
  await until(() => page.evaluate(id => window.qa.transfers[id]?.state === 'offered', empty.id));
  await page.evaluate(id => window.qaPeer.acceptFile(id), empty.id);
  await until(() => page.evaluate(id => window.qa.transfers[id]?.state === 'complete', empty.id));
  assert.equal(await page.evaluate(id => window.qa.transfers[id].blob.size, empty.id), 0);

  const rejected = await api('/file', { name: 'decline.bin', bytes: 'AQID' });
  await until(() => page.evaluate(id => window.qa.transfers[id]?.state === 'offered', rejected.id));
  await page.evaluate(id => window.qaPeer.rejectFile(id), rejected.id);
  await until(async () => (await api('/state')).transfers.find(value => value.id === rejected.id)?.state === 'rejected');
  const cancelled = await api('/file', { name: 'cancel.bin', bytes: 'AQID' });
  await until(() => page.evaluate(id => window.qa.transfers[id]?.state === 'offered', cancelled.id));
  await api('/cancel', { id: cancelled.id });
  await until(() => page.evaluate(id => window.qa.transfers[id]?.state === 'cancelled', cancelled.id));

  const nativeStats = await api('/stats');
  const webStats = await page.evaluate(async () => [...(await window.qaPeer.pc.getStats()).values()]);
  const dtls = webStats.find(value => value.type === 'transport' && value.dtlsState === 'connected');
  assert.ok(dtls, 'native/browser DTLS must be connected');
  assert.match(dtls.dtlsCipher || '', /AES|CHACHA/i);
  assert.ok(webStats.some(value => value.type === 'data-channel' && value.state === 'open'));
  assert.ok(nativeStats.some(value => value.type === 'transport'));
  assert.ok(requests.every(url => url.startsWith(new URL(page.url()).origin + '/')), 'no outside page requests');
  assert.ok(!requests.some(url => /\/api\/(transfer|download)/.test(url)), 'files never use plaintext HTTP routes');

  await api('/close');
  await until(() => page.evaluate(() => window.qa.state === 'closed'));
  await api('/reset'); await initBrowser();
  const webOffer = await page.evaluate(() => window.qaPeer.createOffer());
  const nativeAnswer = await api('/join', { code: webOffer });
  await page.evaluate(code => window.qaPeer.acceptAnswer(code), nativeAnswer.code); await connected();
  await page.evaluate(() => window.qaPeer.sendText('reverse invitation PASS'));
  await until(async () => (await api('/state')).messages.includes('reverse invitation PASS'));
  await api('/close'); await api('/reset'); await initBrowser();
  const honest = await api('/create');
  const decoded = JSON.parse(Buffer.from(honest.code.slice(5), 'base64url').toString());
  decoded.sdp = decoded.sdp.replace(/(a=fingerprint:sha-256 )([A-Fa-f0-9]{2})/, (_match, prefix, byte) => prefix + (byte === '00' ? '01' : '00'));
  const forged = 'IGW1.' + Buffer.from(JSON.stringify(decoded)).toString('base64url');
  const forgedAnswer = await page.evaluate(code => window.qaPeer.acceptOffer(code), forged);
  await api('/answer', { code: forgedAnswer });
  await until(async () => (await api('/state')).state === 'closed' ||
    await page.evaluate(() => window.qa.state === 'closed'));
  assert.notEqual((await api('/state')).state, 'connected', 'forged certificate fingerprint cannot authenticate');
  assert.notEqual(await page.evaluate(() => window.qa.state), 'connected');
  await api('/close');
  const result = { pass: true, dtlsCipher: dtls.dtlsCipher, tlsVersion: dtls.tlsVersion,
    checks: ['both invitation directions', 'matching fingerprint number', 'bidirectional text',
      'exact binary bytes both ways', 'empty file', 'decline', 'cancel', 'disconnect',
      'tampered fingerprint rejected', 'session-bound signed file receipts', 'native/web audit bundle verification',
      'no plaintext HTTP files', 'no outside HTTP requests'] };
  if (process.env.QA_RESULT_FILE) await writeFile(process.env.QA_RESULT_FILE, JSON.stringify(result, null, 2));
  console.log('PASS native Flutter WebRTC ↔ Chromium:', JSON.stringify(result));
} finally { await browser.close(); await api('/close').catch(() => {}); }
