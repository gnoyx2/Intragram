import { t } from './i18n.mjs';

const AAD = new TextEncoder().encode('Intragram Web vault v1');
const encoder = new TextEncoder();
const MAX_BYTES = 4 * 1024 * 1024;
function b64(bytes) { return btoa(Array.from(bytes, b => String.fromCharCode(b)).join('')); }
function unb64(value) { if (typeof value !== 'string' || value.length > MAX_BYTES * 2) throw new Error('vault-invalid'); return Uint8Array.from(atob(value), c => c.charCodeAt(0)); }
async function key(password, salt) {
  const material = await crypto.subtle.importKey('raw', encoder.encode(password), 'PBKDF2', false, ['deriveKey']);
  return crypto.subtle.deriveKey({ name: 'PBKDF2', salt, iterations: 310000, hash: 'SHA-256' }, material, { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}
export async function sealVault(snapshot, password) {
  if (typeof password !== 'string' || password.length < 8 || password.length > 1024) throw { code: 'vault-password' };
  const salt = crypto.getRandomValues(new Uint8Array(16)), iv = crypto.getRandomValues(new Uint8Array(12));
  const plain = encoder.encode(JSON.stringify(snapshot));
  if (plain.length > MAX_BYTES) throw { code: 'vault-too-large' };
  try {
    const cipher = await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: AAD }, await key(password, salt), plain);
    return { v: 1, salt: b64(salt), iv: b64(iv), cipher: b64(new Uint8Array(cipher)) };
  } finally { plain.fill(0); }
}
export async function openVault(record, password) {
  if (!record || record.v !== 1) throw { code: 'vault-invalid' };
  let plain;
  try {
    const salt = unb64(record.salt), iv = unb64(record.iv), cipher = unb64(record.cipher);
    if (salt.length !== 16 || iv.length !== 12 || cipher.length < 16 || cipher.length > MAX_BYTES + 16) throw new Error();
    plain = new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv, additionalData: AAD }, await key(password, salt), cipher));
    const snapshot = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(plain));
    const validChat = chat => chat?.version === 1 && Array.isArray(chat.messages) && chat.messages.length <= 500 && chat.messages.every(m => typeof m.text === 'string' && m.text.length <= 16384 && typeof m.mine === 'boolean' && Number.isFinite(m.ts));
    if (!(validChat(snapshot) || snapshot?.version === 2 && Array.isArray(snapshot.conversations) && snapshot.conversations.length <= 100 && snapshot.conversations.every(validChat))) throw new Error();
    return snapshot;
  } catch { throw { code: 'vault-unlock-failed' }; }
  finally { plain?.fill(0); }
}
export function archiveOf(value) { return value.version === 2 ? value : { version: 2, conversations: [{ ...value, chatId: value.chatId || `legacy-${value.savedAt || 0}` }] }; }
export function mergeArchive(archive, chats) {
  const merged = new Map(archive.conversations.map(chat => [chat.chatId, chat]));
  for (const chat of chats) merged.set(chat.chatId || `legacy-${chat.savedAt || 0}`, chat);
  if (merged.size > 100) throw { code: 'vault-too-large' };
  return { version: 2, conversations: [...merged.values()] };
}
async function storage(action, value, expected, guard = () => {}) {
  guard();
  const db = await new Promise((resolve, reject) => {
    const request = indexedDB.open('intragram-web-vault', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('vault');
    request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error);
  });
  try {
    return await new Promise((resolve, reject) => {
      const transaction = db.transaction('vault', action === 'get' ? 'readonly' : 'readwrite');
      const store = transaction.objectStore('vault');
      const request = action === 'get' || action === 'put' ? store.get('chat') : store.delete('chat');
      let conflict;
      let result; request.onsuccess = () => { result = request.result; };
      if (action === 'put') request.onsuccess = () => {
        try { guard(); } catch (e) { conflict = e; transaction.abort(); return; }
        if (JSON.stringify(request.result) !== JSON.stringify(expected)) { conflict = { code: 'vault-conflict' }; transaction.abort(); return; }
        const mutation = store.put(value, 'chat');
        mutation.onsuccess = () => { try { guard(); } catch (e) { conflict = e; transaction.abort(); } };
      };
      transaction.oncomplete = () => resolve(result); transaction.onabort = () => reject(conflict || transaction.error); transaction.onerror = () => reject(transaction.error);
    });
  } finally { db.close(); }
}
const el = (tag, text) => { const e = document.createElement(tag); if (text) e.textContent = text; return e; };
export class VaultExperience {
  constructor({ snapshot, rename, onError, onPanic }) {
    this.snapshot = snapshot; this.rename = rename; this.onError = onError;
    this.onPanic = onPanic;
    this.epoch = 0;
    this.dialog = el('dialog'); this.dialog.className = 'vault-dialog';
    const title = el('h2'); title.dataset.i18n = 'vault';
    const help = el('p'); help.dataset.i18n = 'vaultHelp'; help.className = 'muted';
    this.password = el('input'); this.password.type = 'password'; this.password.autocomplete = 'off'; this.password.minLength = 8; this.password.maxLength = 1024;
    const passLabel = el('label'); passLabel.dataset.i18n = 'vaultPassword'; this.password.id = 'vault-password'; passLabel.htmlFor = this.password.id;
    this.duress = el('input'); this.duress.type = 'password'; this.duress.autocomplete = 'off'; this.duress.maxLength = 1024; this.duress.id = 'vault-duress';
    const duressLabel = el('label'); duressLabel.dataset.i18n = 'vaultDuress'; duressLabel.htmlFor = this.duress.id;
    this.status = el('p'); this.status.setAttribute('role', 'status'); this.status.className = 'field-hint';
    this.view = el('div'); this.view.className = 'vault-view'; this.view.setAttribute('role', 'log');
    this.savedList = el('select'); this.savedList.id = 'vault-conversations'; this.savedList.hidden = true; this.savedList.setAttribute('aria-label', t('savedConversations'));
    this.savedList.onchange = () => this.showChat(this.opened.conversations[Number(this.savedList.value)]);
    this.actions = el('div'); this.actions.className = 'actions';
    this.button('vaultSave', () => this.save()); this.button('vaultUnlock', () => this.unlock());
    this.button('vaultBackup', () => this.backup()); this.button('vaultImport', () => this.file.click());
    this.button('vaultChangePassword', () => this.changePassword());
    this.button('vaultDeleteChat', () => this.deleteConversation());
    this.button('vaultErase', () => { this.eraseConfirmation.hidden = false; });
    this.button('close', () => { this.lock(); this.dialog.close(); });
    this.file = el('input'); this.file.type = 'file'; this.file.accept = '.json,application/json'; this.file.hidden = true;
    this.file.onchange = () => this.action(async () => {
      const guard = this.guard();
      const file = this.file.files[0]; this.file.value = ''; if (!file) return;
      if (file.size > MAX_BYTES * 2) throw { code: 'vault-invalid' };
      const data = JSON.parse(await file.text()), password = this.password.value;
      const imported = archiveOf(await openVault(data.main, password));
      const existing = await storage('get');
      const archive = existing ? mergeArchive(archiveOf(await openVault(existing.main, password)), imported.conversations) : imported;
      const decoy = existing?.decoy || data.decoy || await sealVault({ version: 2, conversations: [] }, b64(crypto.getRandomValues(new Uint8Array(32))));
      const record = { intragram: 'web-vault', version: 1, main: await sealVault(archive, password), decoy };
      await storage('put', record, existing, guard); guard(); this.show(archive); this.status.textContent = t('vaultImported');
    });
    this.eraseConfirmation = el('div'); this.eraseConfirmation.className = 'notice'; this.eraseConfirmation.hidden = true;
    const warning = el('p'); warning.dataset.i18n = 'vaultEraseWarning'; const erase = el('button'); erase.type = 'button'; erase.className = 'button'; erase.dataset.i18n = 'vaultEraseConfirm';
    erase.onclick = () => { this.lock(); return this.action(async () => { await storage('delete'); this.view.replaceChildren(); this.eraseConfirmation.hidden = true; this.status.textContent = t('vaultErased'); }); };
    this.eraseConfirmation.append(warning, erase);
    const newPasswordLabel = el('label'); newPasswordLabel.dataset.i18n = 'vaultNewPassword'; this.newPassword = el('input'); this.newPassword.type = 'password'; this.newPassword.autocomplete = 'new-password'; this.newPassword.maxLength = 1024; this.newPassword.id = 'vault-new-password'; newPasswordLabel.htmlFor = this.newPassword.id;
    this.dialog.append(title, help, passLabel, this.password, duressLabel, this.duress, newPasswordLabel, this.newPassword, this.actions, this.eraseConfirmation, this.status, this.savedList, this.view, this.file); document.body.append(this.dialog);
    this.dialog.addEventListener('close', () => this.lock());
    this.dialog.addEventListener('cancel', () => this.lock());
    document.getElementById('global-vault').onclick = () => document.getElementById('vault-open').click();
    document.getElementById('global-settings').onclick = () => document.getElementById('settings-open').click();
    document.getElementById('vault-open').onclick = () => { this.refresh(); this.dialog.showModal(); this.password.focus(); };
    this.settings = el('dialog'); this.settings.className = 'settings-dialog';
    const settingsTitle = el('h2'); settingsTitle.dataset.i18n = 'settings';
    const label = el('label'); label.dataset.i18n = 'displayName'; this.alias = el('input'); this.alias.type = 'text'; this.alias.maxLength = 80; this.alias.id = 'display-name'; label.htmlFor = this.alias.id;
    this.alias.onchange = () => this.rename(this.alias.value);
    this.privacy = el('input'); this.privacy.type = 'checkbox'; this.privacy.id = 'privacy-blur'; const privacyLabel = el('label'); privacyLabel.htmlFor = this.privacy.id; privacyLabel.dataset.i18n = 'privacyBlur';
    const notification = el('button'); notification.type = 'button'; notification.className = 'button'; notification.dataset.i18n = 'enableNotifications';
    notification.onclick = () => this.action(async () => { if (!('Notification' in window)) throw { code: 'notifications-unavailable' }; const result = await Notification.requestPermission(); notification.textContent = t(result === 'granted' ? 'notificationsEnabled' : 'notificationsDenied'); });
    const clear = el('button'); clear.type = 'button'; clear.className = 'button'; clear.dataset.i18n = 'panic'; clear.onclick = () => { this.settings.close(); this.lock(); onPanic?.(); };
    const panic = el('button'); panic.id = 'panic-all'; panic.type = 'button'; panic.className = 'button'; panic.dataset.i18n = 'panicAll'; panic.onclick = () => this.panicDialog.showModal();
    const close = el('button'); close.type = 'button'; close.className = 'button'; close.dataset.i18n = 'close'; close.onclick = () => this.settings.close();
    const settingsActions = el('div'); settingsActions.className = 'actions'; settingsActions.append(notification, clear, panic, close);
    this.settings.append(settingsTitle, label, this.alias, this.privacy, privacyLabel, settingsActions); document.body.append(this.settings);
    document.getElementById('settings-open').onclick = () => { this.refresh(); this.settings.showModal(); };
    this.panicDialog = el('dialog'); this.panicDialog.className = 'panic-dialog';
    const panicTitle = el('h2'); panicTitle.dataset.i18n = 'panicAll';
    const panicBody = el('p'); panicBody.dataset.i18n = 'panicAllWarning';
    const panicCancel = el('button'); panicCancel.type = 'button'; panicCancel.className = 'button'; panicCancel.dataset.i18n = 'cancel'; panicCancel.onclick = () => this.panicDialog.close();
    const panicConfirm = el('button'); panicConfirm.id = 'panic-confirm'; panicConfirm.type = 'button'; panicConfirm.className = 'button primary'; panicConfirm.dataset.i18n = 'panicAllConfirm'; panicConfirm.onclick = () => this.panicAll();
    const panicActions = el('div'); panicActions.className = 'actions'; panicActions.append(panicCancel, panicConfirm);
    this.panicDialog.append(panicTitle, panicBody, panicActions); document.body.append(this.panicDialog);
    if ('BroadcastChannel' in globalThis) {
      this.channel = new BroadcastChannel('intragram-web-session');
      this.channel.onmessage = event => { if (event.data?.type === 'panic') this.panicAll(false); };
    }
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) { this.lock(); if (this.dialog.open) this.dialog.close(); }
      document.body.classList.toggle('privacy-hidden', this.privacy.checked && document.hidden);
    });
    window.addEventListener('pagehide', () => this.lock());
    this.refresh();
  }
  button(key, action) { const b = el('button'); b.type = 'button'; b.className = 'button'; b.dataset.i18n = key; b.dataset.vaultAction = key; b.onclick = () => this.action(action); this.actions.append(b); }
  async action(action) {
    if (this.panicking) return;
    const epoch = this.epoch;
    for (const b of this.actions.querySelectorAll('button')) b.disabled = true;
    try { await action(); } catch (e) { if (epoch === this.epoch) this.status.textContent = t(e?.code || 'vault-invalid'); }
    finally { if (epoch === this.epoch) for (const b of this.actions.querySelectorAll('button')) b.disabled = false; }
  }
  guard() { const epoch = this.epoch; return () => { if (this.panicking || epoch !== this.epoch) throw { code: 'vault-locked' }; }; }
  async panicAll(broadcast = true) {
    if (this.panicking) return;
    this.panicking = true;
    this.lock(); this.dialog.close(); this.settings.close(); this.panicDialog.close();
    if (broadcast) this.channel?.postMessage({ type: 'panic' });
    try { this.onPanic?.({ all: true }); await storage('delete'); }
    catch (error) { this.onError(error); }
    finally { this.panicking = false; }
  }
  async save() {
    const guard = this.guard();
    const snapshot = this.snapshot(), password = this.password.value, duressPassword = this.duress.value;
    const existing = await storage('get');
    const archive = existing ? archiveOf(await openVault(existing.main, password)) : { version: 2, conversations: [] };
    const main = await sealVault(mergeArchive(archive, [snapshot]), password);
    let decoy = existing?.decoy;
    if (duressPassword) {
      if (duressPassword === password) throw { code: 'vault-duress-same' };
      decoy = await sealVault({ version: 2, conversations: [] }, duressPassword);
    }
    decoy ||= await sealVault({ version: 2, conversations: [] }, b64(crypto.getRandomValues(new Uint8Array(32))));
    await storage('put', { intragram: 'web-vault', version: 1, main, decoy }, existing, guard); guard();
    this.status.textContent = t('vaultSaved'); this.password.value = ''; this.duress.value = '';
  }
  async changePassword() {
    const guard = this.guard();
    const existing = await storage('get'); if (!existing) throw { code: 'vault-empty' };
    const current = this.password.value, next = this.newPassword.value;
    const archive = await openVault(existing.main, current);
    if (existing.decoy) {
      let same = false; try { await openVault(existing.decoy, next); same = true; } catch {}
      if (same) throw { code: 'vault-duress-same' };
    }
    await storage('put', { ...existing, main: await sealVault(archive, next) }, existing, guard); guard();
    this.lock(); this.status.textContent = t('vaultPasswordChanged');
  }
  async deleteConversation() {
    const guard = this.guard();
    const selected = this.opened?.conversations[Number(this.savedList.value)]; if (!selected) throw { code: 'vault-empty' };
    const existing = await storage('get'), password = this.password.value;
    const archive = archiveOf(await openVault(existing.main, password));
    archive.conversations = archive.conversations.filter(chat => chat.chatId !== selected.chatId);
    await storage('put', { ...existing, main: await sealVault(archive, password) }, existing, guard); guard(); this.show(archive); this.password.value = '';
  }
  async decrypt(record) {
    if (record?.intragram !== 'web-vault' || record.version !== 1) throw { code: 'vault-invalid' };
    try { return await openVault(record.main, this.password.value); }
    catch { if (record.decoy) return openVault(record.decoy, this.password.value); throw { code: 'vault-unlock-failed' }; }
  }
  async unlock() { const guard = this.guard(); const record = await storage('get'); if (!record) throw { code: 'vault-empty' }; const opened = await this.decrypt(record); guard(); this.show(opened); this.password.value = ''; this.duress.value = ''; }
  show(snapshot) {
    if (!this.dialog.open) return;
    this.opened = archiveOf(snapshot); this.savedList.replaceChildren(); this.savedList.hidden = !this.opened.conversations.length;
    this.opened.conversations.forEach((chat, index) => { const option = el('option', `${chat.peerAlias || t('savedConversation')} · ${new Date(chat.savedAt || chat.messages[0]?.ts || Date.now()).toLocaleString()}`); option.value = String(index); this.savedList.append(option); });
    this.savedList.value = String(Math.max(0, this.opened.conversations.length - 1));
    this.showChat(this.opened.conversations.at(-1));
  }
  showChat(snapshot) {
    this.view.replaceChildren();
    for (const m of snapshot?.messages || []) {
      const row = el('div'); row.className = `message${m.mine ? ' mine' : ''}`; row.append(el('p', m.text), el('small', new Date(m.ts).toLocaleString())); this.view.append(row);
    }
    this.status.textContent = snapshot?.messages.length ? t('vaultUnlocked') : t('vaultEmptyView');
  }
  async backup() {
    const guard = this.guard();
    const record = await storage('get'); if (!record) throw { code: 'vault-empty' };
    guard();
    const url = URL.createObjectURL(new Blob([JSON.stringify(record)], { type: 'application/json' }));
    const link = el('a'); link.href = url; link.download = 'Intragram-encrypted-vault.json'; document.body.append(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 10000);
    this.status.textContent = t('vaultBackupDone');
  }
  lock() { this.epoch++; this.password.value = ''; this.duress.value = ''; this.newPassword.value = ''; this.view.replaceChildren(); this.savedList.replaceChildren(); this.savedList.hidden = true; this.opened = null; this.status.textContent = ''; this.eraseConfirmation.hidden = true; for (const b of this.actions.querySelectorAll('button')) b.disabled = false; }
  refresh() { for (const item of [...this.dialog.querySelectorAll('[data-i18n]'), ...this.settings.querySelectorAll('[data-i18n]'), ...this.panicDialog.querySelectorAll('[data-i18n]')]) item.textContent = t(item.dataset.i18n); }
}
