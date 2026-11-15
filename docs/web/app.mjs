import { MAX_FILE_BYTES } from './peer.mjs';
import { RoomSession } from './room.mjs';
import { t, language, setLanguage, applyTranslations } from './i18n.mjs';
import { ChatExperience } from './chat.mjs';
import { MediaExperience } from './media.mjs';
import { VaultExperience } from './vault.mjs';
import { EvidenceExperience } from './evidence-ui.mjs';
import { FileQueue } from './file-queue.mjs';
import { receiveBudget } from './receive-budget.mjs';

// 다른 페이지의 프레임 안에서는 동작하지 않고 새 탭 링크만 보여 줌: 보이지 않는 프레임으로 클릭을 유도하지 못함.
// 정적 호스팅은 응답 헤더(frame-ancestors)를 못 넣어서 페이지가 직접 확인함
if (window.top !== window.self) {
  const open = Object.assign(document.createElement('a'), { href: location.href, target: '_blank', rel: 'noopener noreferrer', textContent: '새 탭에서 열기 · Open in a new tab' });
  const note = Object.assign(document.createElement('p'), { className: 'notice' });
  note.append('다른 사이트 안에서는 열리지 않습니다. · This page does not open inside another site. ', open);
  document.body.replaceChildren(note);
  await new Promise(() => {}); // 모듈의 나머지를 실행하지 않음
}

const $ = id => document.getElementById(id);
const params = new URLSearchParams(location.search);
setLanguage(params.get('lang') || (/^ko\b/i.test(navigator.language) ? 'ko' : 'en'));
let theme = ['light', 'dark'].includes(params.get('theme')) ? params.get('theme') : 'system';
let mode = 'create', exchangeType = '', session, busy = false;
let pendingMode = 'create';
const transfers = new Map();
const urls = new Map();
let retainedBytes = 0;
const chatExperience = new ChatExperience({ getSession: () => session, onError: showError, onBurn: message => evidenceExperience.burn(message) });
const mediaExperience = new MediaExperience({ getSession: () => session, onError: showError, offerFile: file => fileQueue.add([file]) });
const vaultExperience = new VaultExperience({ snapshot: () => chatExperience.snapshot(), rename: value => chatExperience.rename(value), onError: showError,
  onPanic: ({ all = false } = {}) => { vaultExperience.lock(); clearSession({ rotateIdentity: all }); newSession(); clearError(); showMode('create'); updateState('idle'); } });
const evidenceExperience = new EvidenceExperience({ getSession: () => session, onError: showError });
const fileQueue = new FileQueue({ getSession: () => session, onError: showError });

function announce(key) { $('announcement').textContent = t(key); }
function showError(error) {
  $('error').textContent = t(error?.code || 'genericError');
  $('error').hidden = false;
}
function clearError() { $('error').hidden = true; $('error').textContent = ''; }
function updatePreferences() {
  $('language').value = language;
  $('theme').value = theme;
  if (theme === 'system') delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = theme;
  applyTranslations();
  const query = new URLSearchParams({ lang: language });
  if (theme !== 'system') query.set('theme', theme);
  if (mode === 'portal') query.set('mode', 'portal');
  history.replaceState(null, '', `${location.pathname}?${query}`);
  for (const [id, hash] of [['home-link', ''], ['download-link', '#install'], ['security-link', '#security']]) {
    $(id).href = `../?${query}${hash}`;
  }
  updateState(session?.state || 'idle');
  updateExchangeText();
  for (const transfer of transfers.values()) renderTransfer(transfer);
  chatExperience.refresh();
  vaultExperience.refresh();
  evidenceExperience.refresh();
  fileQueue.refresh();
}
function updateExchangeText() {
  if (!exchangeType) return;
  $('exchange-title').textContent = t(exchangeType === 'offer' ? 'offerTitle' : 'answerTitle');
  $('exchange-help').textContent = t(exchangeType === 'offer' ? 'offerHelp' : 'answerHelp');
  $('local-code-label').textContent = t(exchangeType === 'offer' ? 'myOffer' : 'myAnswer');
}
function setBusy(value) {
  busy = value;
  for (const id of ['create-offer', 'accept-offer', 'accept-answer', 'mode-create', 'mode-join', 'mode-portal']) $(id).disabled = value;
}
function updateState(state) {
  if (state === 'closed') fileQueue.clear();
  $('connection-status').textContent = t(state);
  $('connection-status').dataset.state = state;
  $('reset').hidden = state === 'idle' && !transfers.size && !$('messages').querySelector('.message');
  const connected = state === 'connected';
  if (connected) queueMicrotask(() => { if (session?.state === 'connected') fileQueue.advance(); });
  for (const id of ['attach', 'send', 'message-input']) $(id).disabled = !connected;
  if (connected) {
    $('setup').hidden = true;
    const wasHidden = $('chat').hidden;
    $('chat').hidden = false;
    document.body.classList.add('in-chat');
    $('verification-code').textContent = session.verificationCode;
    $('local-code').value = '';
    $('invite-code').value = '';
    $('answer-code').value = '';
    if (wasHidden) $('message-input').focus({ preventScroll: true });
    if (wasHidden) chatExperience.connected();
  }
}
function newSession() {
  const next = new RoomSession({
    onState: state => { if (session === next) updateState(state); },
    onMessage: message => { if (session === next) chatExperience.add(message, false); },
    onControl: control => { if (session === next) chatExperience.control(control); },
    onRoom: room => { if (session === next) updateRoom(room); },
    onPeerState: (id, state) => { if (session === next && state === 'connected') evidenceExperience.attach(next.peers.get(id)); },
    onEvidence: (record, control) => { if (session === next) evidenceExperience.receive(record, control); },
    onFileOffered: (record, id, file) => { if (session === next) evidenceExperience.expectFile(record, id, file); },
    onTransfer: transfer => { if (session === next) onTransfer(transfer); },
    onError: error => { if (session === next) showError(error); },
  });
  session = next;
}
function updateRoom(room) {
  chatExperience.setRoom(room);
  $('add-person').hidden = !room.isHost;
  const selected = session.primary?.id;
  $('file-peer').replaceChildren();
  const recipients = room.isHost ? room.members.filter(m => m.id !== room.self) : room.members.filter(m => m.id === room.host);
  for (const peer of recipients) { const option = document.createElement('option'); option.value = room.isHost ? peer.id : session.primary.id; option.textContent = peer.alias; $('file-peer').append(option); }
  if ([...$('file-peer').options].some(o => o.value === selected)) $('file-peer').value = selected;
  $('room-note').hidden = room.members.length < 3;
}
function showMode(nextMode) {
  mode = nextMode;
  for (const name of ['create', 'join', 'portal']) $(`mode-${name}`).setAttribute('aria-pressed', String(name === mode));
  $('create-view').hidden = mode !== 'create';
  $('join-form').hidden = mode !== 'join';
  $('portal-guide').hidden = mode !== 'portal';
  $('exchange-view').hidden = true;
  $('setup').hidden = false;
  $('chat').hidden = true;
  document.body.classList.remove('in-chat');
  const url = new URL(location.href);
  if (mode === 'portal') url.searchParams.set('mode', 'portal');
  else url.searchParams.delete('mode');
  history.replaceState(null, '', url);
}
function clearSession({ rotateIdentity = false } = {}) {
  const previous = session;
  session = null;
  previous?.close();
  chatExperience.clear(); mediaExperience.stop(true);
  vaultExperience.lock(); evidenceExperience.clear({ rotateIdentity });
  fileQueue.clear();
  for (const url of urls.values()) URL.revokeObjectURL(url);
  urls.clear(); transfers.clear(); retainedBytes = 0;
  $('messages').querySelectorAll('.transfer').forEach(el => el.remove());
  $('messages').querySelectorAll('.message').forEach(el => el.remove());
  $('chat-empty').hidden = false;
  for (const id of ['local-code', 'invite-code', 'answer-code', 'message-input', 'file-input']) $(id).value = '';
  $('verification-code').textContent = '';
  exchangeType = '';
  $('cancel-invite').hidden = true;
  setBusy(false);
}
function requestReset(nextMode) {
  pendingMode = nextMode;
  if (session.state !== 'idle' || transfers.size || $('messages').querySelector('.message')) {
    $('reset-dialog').showModal();
  } else { clearError(); showMode(nextMode); }
}
async function run(action) {
  clearError();
  try { await action(); } catch (error) { showError(error); }
}
async function negotiate(action, type) {
  if (busy) return;
  if (session.state === 'closed') { clearSession(); newSession(); }
  const current = session;
  setBusy(true);
  try {
    const code = await action(current);
    if (session !== current) return;
    if (code) {
      exchangeType = type;
      updateExchangeText();
      $('local-code').value = code;
      $('create-view').hidden = true;
      $('join-form').hidden = true;
      $('exchange-view').hidden = false;
      $('answer-form').hidden = type !== 'offer';
      $('waiting-answer').hidden = type === 'offer';
      $('local-code').focus({ preventScroll: true });
    }
  } catch (error) { if (session === current) showError(error); }
  finally { if (session === current) setBusy(false); }
}
function formatSize(size) { return size < 1024 ? `${size} B` : size < 1048576 ? `${(size / 1024).toFixed(1)} KiB` : `${(size / 1048576).toFixed(1)} MiB`; }
function discardTransfer(id) {
  const transfer = transfers.get(id);
  if (!transfer) return;
  if (transfer.blob) retainedBytes -= transfer.size;
  if (urls.has(id)) URL.revokeObjectURL(urls.get(id));
  urls.delete(id); transfers.delete(id); document.getElementById(`transfer-${id}`)?.remove();
  if (!$('messages').querySelector('.message, .transfer')) $('chat-empty').hidden = false;
}
function onTransfer(transfer) {
  fileQueue.transfer(transfer);
  evidenceExperience.received(transfer);
  if (transfer.blob && !transfers.get(transfer.id)?.blob) {
    retainedBytes += transfer.size;
    urls.set(transfer.id, URL.createObjectURL(transfer.blob));
  }
  const previous = transfers.get(transfer.id);
  if (transfer.state === 'transferring') {
    transfer.startedAt = previous?.startedAt || performance.now();
    const elapsed = (performance.now() - transfer.startedAt) / 1000;
    if (elapsed > .25) { transfer.speed = transfer.transferred / elapsed; transfer.remainingSeconds = Math.ceil((transfer.size - transfer.transferred) / transfer.speed); }
  }
  transfers.set(transfer.id, transfer);
  if (transfers.size > 100) {
    for (const item of transfers.values()) {
      if (item.id !== transfer.id && !item.blob && !['offered', 'transferring'].includes(item.state)) { discardTransfer(item.id); break; }
    }
  }
  renderTransfer(transfer);
  if (transfer.state === 'offered' || transfer.state === 'complete') announce(transfer.state);
}
function renderTransfer(transfer) {
  let el = document.getElementById(`transfer-${transfer.id}`);
  const created = !el;
  if (!el) {
    el = document.createElement('div'); el.id = `transfer-${transfer.id}`; el.className = 'transfer';
    el.setAttribute('aria-live', 'off'); $('messages').append(el); $('chat-empty').hidden = true;
  }
  if (el.dataset.state === 'transferring' && transfer.state === 'transferring' && el.dataset.language === language) {
    el.querySelector('progress').value = transfer.transferred;
    if (transfer.speed) el.querySelector('p').textContent = `${formatSize(transfer.transferred)} / ${formatSize(transfer.size)} · ${formatSize(transfer.speed)}/s · ${transfer.remainingSeconds}s`;
    return;
  }
  el.dataset.language = language;
  el.dataset.direction = transfer.direction; el.dataset.state = transfer.state;
  const focusedAction = el.contains(document.activeElement) ? document.activeElement.dataset.action : null;
  const name = document.createElement('strong'); name.textContent = transfer.name;
  const state = document.createElement('p');
  state.textContent = `${t(transfer.direction === 'send' ? 'sending' : 'received')}${transfer.peerAlias ? ` · ${transfer.peerAlias}` : ''} · ${formatSize(transfer.size)} · ${t(transfer.state)}`;
  el.replaceChildren(name, state);
  if (transfer.state === 'transferring') {
    const progress = document.createElement('progress');
    progress.max = transfer.size || 1; progress.value = transfer.transferred;
    progress.setAttribute('aria-label', t('transferring')); el.append(progress);
  }
  const actions = document.createElement('div'); actions.className = 'actions'; el.append(actions);
  const button = (key, action) => {
    const control = document.createElement('button'); control.type = 'button'; control.className = 'button small'; control.textContent = t(key); control.dataset.action = key;
    control.onclick = () => run(action); actions.append(control);
  };
  if (transfer.state === 'offered' && transfer.direction === 'receive') {
    button('accept', () => {
      const budget = receiveBudget(transfers.values());
      if (budget.bytes + transfer.size > MAX_FILE_BYTES || budget.files >= 100) throw { code: 'receive-budget' };
      session.acceptFile(transfer.id);
    });
    button('reject', () => session.rejectFile(transfer.id));
  }
  if (['offered', 'transferring'].includes(transfer.state)) button('cancel', () => session.cancelFile(transfer.id));
  else {
    if (transfer.direction === 'send' && ['failed', 'rejected', 'cancelled'].includes(transfer.state)) button('retryFile', () => $('file-input').click());
    if (urls.has(transfer.id)) {
      const link = document.createElement('a'); link.className = 'button small'; link.href = urls.get(transfer.id); link.download = transfer.name; link.textContent = t('save'); link.dataset.action = 'save'; actions.append(link);
      mediaExperience.preview(el, transfer, urls.get(transfer.id));
    }
    button('discard', () => discardTransfer(transfer.id));
  }
  if (focusedAction) actions.querySelector(`[data-action="${focusedAction}"]`)?.focus({ preventScroll: true });
  if (created) $('messages').scrollTop = $('messages').scrollHeight;
}

$('language').onchange = () => { setLanguage($('language').value); updatePreferences(); };
$('theme').onchange = () => { theme = $('theme').value; updatePreferences(); };
for (const name of ['create', 'join', 'portal']) $(`mode-${name}`).onclick = () => requestReset(name);
$('reset').onclick = () => requestReset('create');
$('add-person').onclick = () => run(async () => {
  $('chat').hidden = true; $('setup').hidden = false;
  $('create-view').hidden = true; $('join-form').hidden = true;
  $('cancel-invite').hidden = false;
  await negotiate(s => s.createOffer(), 'offer');
});
$('cancel-invite').onclick = () => { session.cancelInvitation(); $('cancel-invite').hidden = true; updateState(session.state); };
$('file-peer').onchange = () => { session.selectPeer($('file-peer').value); chatExperience.updateVerification(); };
for (const id of ['new-chat', 'global-new-chat']) $(id).onclick = () => {
  const url = new URL(location.href); url.searchParams.delete('mode');
  window.open(url, '_blank', 'noopener,noreferrer');
};
$('keep-session').onclick = () => $('reset-dialog').close();
$('end-session').onclick = () => { $('reset-dialog').close(); clearSession(); newSession(); clearError(); showMode(pendingMode); updateState('idle'); };
$('create-offer').onclick = () => { clearError(); return negotiate(s => s.createOffer(), 'offer'); };
$('join-form').onsubmit = event => {
  event.preventDefault(); clearError();
  const input = $('invite-code').value.trim();
  if (input.startsWith('IGA1.') || /^https?:/i.test(input)) return showError({ code: 'legacy-portal' });
  return negotiate(s => s.acceptOffer(input), 'answer');
};
$('answer-form').onsubmit = event => { event.preventDefault(); clearError(); return negotiate(s => s.acceptAnswer($('answer-code').value)); };
$('copy-code').onclick = async () => {
  try { await navigator.clipboard.writeText($('local-code').value); announce('copied'); }
  catch { $('local-code').focus(); $('local-code').select(); announce('copyFallback'); }
};
$('join-app').onclick = () => { showMode('join'); $('invite-code').focus(); };
$('message-form').onsubmit = event => {
  event.preventDefault(); if (!$('message-input').value.trim()) return;
  run(() => { const value = $('message-input').value; const id = session.sendText(value); chatExperience.sent(id, value); $('message-input').value = ''; $('message-input').focus(); });
};
$('message-input').onkeydown = event => {
  if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) { event.preventDefault(); $('message-form').requestSubmit(); }
};
$('attach').onclick = () => $('file-input').click();
$('file-input').onchange = () => run(() => { const files = [...$('file-input').files]; $('file-input').value = ''; if (files.length) fileQueue.add(files); });
$('chat').ondragover = event => { if (event.dataTransfer.types.includes('Files')) { event.preventDefault(); $('chat').classList.add('dragging'); } };
$('chat').ondragleave = event => { if (!$('chat').contains(event.relatedTarget)) $('chat').classList.remove('dragging'); };
$('chat').ondrop = event => { event.preventDefault(); $('chat').classList.remove('dragging'); run(() => fileQueue.add([...event.dataTransfer.files])); };
window.addEventListener('beforeunload', event => {
  if (session && session.state !== 'idle' && session.state !== 'closed' || transfers.size || $('messages').querySelector('.message')) { event.preventDefault(); event.returnValue = ''; }
});
window.addEventListener('pagehide', () => { clearSession({ rotateIdentity: true }); });
window.addEventListener('pageshow', event => { if (event.persisted) { newSession(); showMode('create'); updateState('idle'); } });
newSession();
if (params.get('mode') === 'portal') showMode('portal');
updatePreferences();
if (!window.isSecureContext || !window.RTCPeerConnection || !crypto.subtle) {
  $('create-offer').disabled = true; $('accept-offer').disabled = true; showError({ code: 'unsupported-browser' });
}
