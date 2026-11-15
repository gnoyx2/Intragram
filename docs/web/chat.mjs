import { REACTIONS, newId } from './protocol.mjs';
import { t, language } from './i18n.mjs';

const $ = id => document.getElementById(id);
const el = (tag, text, cls) => { const node = document.createElement(tag); if (text !== undefined) node.textContent = text; if (cls) node.className = cls; return node; };

// Controls refer only to messages from this live authenticated session.
export class ChatExperience {
  constructor({ getSession, onError, onBurn }) {
    this.getSession = getSession; this.onError = onError;
    this.onBurn = onBurn;
    this.messages = new Map(); this.seenMessageIds = new Set(); this.pendingReads = new Set(); this.timers = new Set();
    this.alias = ''; this.peerAlias = ''; this.replyTo = null; this.localVerified = false; this.peerVerified = false;
    this.typingAt = 0; this.unread = 0;
    this.names = new Map(); this.verifiedPeers = new Set(); this.locallyVerifiedPeers = new Set();
    this.chatId = newId();
    $('message-search').oninput = () => this.search();
    $('cancel-reply').onclick = () => this.reply(null);
    $('verify-peer').onclick = () => this.verify();
    $('jump-latest').onclick = () => { $('messages').scrollTop = $('messages').scrollHeight; this.unread = 0; this.updateUnread(); };
    $('message-input').addEventListener('input', () => this.typing());
    $('messages').addEventListener('scroll', () => { if (this.atBottom()) { this.unread = 0; this.updateUnread(); this.flushReads(); } });
    document.addEventListener('visibilitychange', () => { if (!document.hidden) this.flushReads(); });
    document.addEventListener('keydown', e => {
      const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(e.target?.tagName) || e.target?.isContentEditable;
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'f' && !$('chat').hidden) { e.preventDefault(); $('message-search').focus(); }
      if (e.key === '/' && !typing && !$('chat').hidden) { e.preventDefault(); $('message-input').focus(); }
      if (e.key === 'Escape') this.reply(null);
    });
  }
  send(control) { try { this.getSession()?.sendControl(control); } catch (e) { this.onError(e); } }
  atBottom() { const log = $('messages'); return log.scrollHeight - log.scrollTop - log.clientHeight < 72; }
  connected() { if (this.alias) this.send({ k: 'rename', alias: this.alias }); this.updateVerification(); }
  rename(alias) { this.alias = alias.trim().slice(0, 80); if (this.alias && this.getSession()?.state === 'connected') this.send({ k: 'rename', alias: this.alias }); }
  typing() {
    const now = Date.now();
    if (now - this.typingAt < 1600 || this.getSession()?.state !== 'connected') return;
    this.typingAt = now; this.send({ k: 'typing', on: !!$('message-input').value.trim() });
  }
  add(frame, mine) {
    if (!frame.id || this.seenMessageIds.has(frame.id)) return;
    this.seenMessageIds.add(frame.id);
    const atBottom = this.atBottom();
    const message = { id: frame.id, text: frame.text, mine, origin: frame.origin || this.getSession()?.selfId, alias: frame.alias, ts: Date.now(), ttl: 0, reactions: new Map(), readBy: new Set(), deliveredBy: new Set(), audience: (this.getSession()?.roster || []).filter(p => p.id !== this.getSession()?.selfId).map(p => p.id), row: el('div', undefined, `message${mine ? ' mine' : ''}`) };
    message.row.dataset.id = frame.id;
    this.messages.set(frame.id, message);
    $('chat-empty').hidden = true;
    $('messages').append(message.row);
    this.render(message);
    while (this.messages.size > 500) this.remove(this.messages.keys().next().value);
    if (mine || atBottom) $('messages').scrollTop = $('messages').scrollHeight;
    else { this.unread++; this.updateUnread(); }
    if (!mine) {
      this.send({ k: 'receipt', id: frame.id }); this.pendingReads.add(frame.id); this.flushReads();
      $('typing-status').textContent = '';
      if (document.hidden && 'Notification' in window && Notification.permission === 'granted') {
        // Notifications contain no message body, including on the lock screen.
        const notification = new Notification('Intragram', { body: t('newMessageNotification'), tag: 'intragram-message' });
        notification.onclick = () => { window.focus(); notification.close(); };
      }
    }
    this.search();
  }
  sent(id, text) {
    this.add({ id, text }, true);
    const m = this.messages.get(id), ttl = Number($('burn-ttl').value);
    m.ttl = ttl;
    const meta = { k: 'meta', id, ttl };
    if (this.replyTo) { meta.replyTo = this.replyTo.id; meta.quote = this.replyTo.text.slice(0, 500); m.replyTo = meta.replyTo; m.quote = meta.quote; }
    this.send(meta); this.send({ k: 'typing', on: false });
    this.render(m); this.reply(null);
  }
  control(c) {
    const m = this.messages.get(c.id);
    switch (c.k) {
      case 'typing': {
        clearTimeout(this.typingTimer);
        $('typing-status').textContent = c.on ? `${this.peerAlias || t('theirs')} ${t('typingNow')}` : '';
        this.typingTimer = setTimeout(() => { $('typing-status').textContent = ''; }, 4000); break;
      }
      case 'rename': this.peerAlias = c.alias; if (c.origin) this.names.set(c.origin, c.alias); for (const msg of this.messages.values()) if (!msg.mine) this.render(msg); break;
      case 'receipt': if (m?.mine) { m.delivered = true; m.deliveredBy.add(c.origin || 'peer'); this.render(m); } break;
      case 'read': if (m?.mine) { m.read = true; m.readBy.add(c.origin || 'peer'); this.startBurn(m); this.render(m); } break;
      case 'meta':
        if (m && !m.mine && (!c.origin || m.origin === c.origin)) { m.ttl = c.ttl; m.replyTo = c.replyTo; m.quote = c.quote; this.startBurn(m); this.render(m); } break;
      case 'burn': if (m && !m.mine && (!c.origin || m.origin === c.origin)) this.remove(c.id, true); break;
      case 'react':
        if (m) { if (c.on) m.reactions.set(c.origin || 'peer', c.emoji); else m.reactions.delete(c.origin || 'peer'); this.render(m); } break;
      case 'verify': if (c.sas === (c.linkSas || this.getSession()?.verificationCode)) { this.verifiedPeers.add(c.linkId || this.getSession()?.primary?.id || 'peer'); this.updateVerification(); } break;
    }
  }
  flushReads() {
    if (document.hidden || !this.atBottom() || this.getSession()?.state !== 'connected') return;
    for (const id of this.pendingReads) { const m = this.messages.get(id); if (m) { m.read = true; this.send({ k: 'read', id }); this.startBurn(m); } }
    this.pendingReads.clear();
  }
  startBurn(m) {
    if (!m.read || !m.ttl || m.burnAt || m.mine && m.audience.length > 1 && m.readBy.size < m.audience.length) return;
    m.burnAt = Date.now() + m.ttl * 1000;
    const timer = setTimeout(() => { this.timers.delete(timer); this.remove(m.id, true); }, m.ttl * 1000);
    m.timer = timer; this.timers.add(timer);
  }
  remove(id, recordBurn = false) {
    const m = this.messages.get(id); if (!m) return;
    if (recordBurn) this.onBurn?.(m);
    clearTimeout(m.timer); this.timers.delete(m.timer); m.row.remove(); this.messages.delete(id); this.pendingReads.delete(id);
    for (const other of this.messages.values()) if (other.replyTo === id) { other.quote = undefined; other.replyTo = undefined; this.render(other); }
    if (this.replyTo?.id === id) this.reply(null);
    if (!$('messages').querySelector('.message,.transfer')) $('chat-empty').hidden = false;
  }
  render(m) {
    const focused = m.row.contains(document.activeElement) ? document.activeElement.dataset.action : null;
    const quote = m.quote ? el('blockquote', m.quote, 'quoted-message') : null;
    const text = el('p', m.text), meta = el('small');
    const time = new Date(m.ts).toLocaleTimeString(language, { hour: '2-digit', minute: '2-digit' });
    meta.textContent = `${m.mine ? this.alias || t('mine') : this.names.get(m.origin) || m.alias || this.peerAlias || t('theirs')} · ${time}${m.mine ? ` · ${t(m.read ? 'read' : m.delivered ? 'delivered' : 'sent')}${m.audience.length > 1 ? ` ${m.read ? m.readBy.size : m.deliveredBy.size}/${m.audience.length}` : ''}` : ''}${m.ttl ? ` · ${m.ttl}s ${t('burnAfterRead')}` : ''}`;
    const actions = el('div', undefined, 'message-actions');
    const button = (key, action, text = t(key)) => {
      const b = el('button', text); b.type = 'button'; b.dataset.action = key; b.onclick = action; actions.append(b); return b;
    };
    button('reply', () => this.reply(m));
    button('copyMessage', async () => { try { await navigator.clipboard.writeText(m.text); } catch (e) { this.onError(e); } });
    const reaction = button('react', () => { reactions.hidden = !reactions.hidden; reaction.setAttribute('aria-expanded', String(!reactions.hidden)); });
    reaction.setAttribute('aria-expanded', 'false');
    button('deleteLocal', () => this.remove(m.id));
    if (m.mine) button('deleteEveryone', () => { this.send({ k: 'burn', id: m.id }); this.remove(m.id, true); });
    const reactions = el('div', undefined, 'reaction-picker'); reactions.hidden = true;
    for (const emoji of REACTIONS) { const b = el('button', emoji); b.type = 'button'; b.setAttribute('aria-label', `${t('react')} ${emoji}`); b.onclick = () => { const on = m.reactions.get('mine') !== emoji; if (on) m.reactions.set('mine', emoji); else m.reactions.delete('mine'); this.send({ k: 'react', id: m.id, emoji, on }); this.render(m); }; reactions.append(b); }
    const chips = el('div', undefined, 'reaction-chips');
    for (const emoji of new Set(m.reactions.values())) chips.append(el('span', `${emoji} ${[...m.reactions.values()].filter(e => e === emoji).length}`));
    m.row.replaceChildren(...(quote ? [quote] : []), text, meta, chips, actions, reactions);
    if (focused) m.row.querySelector(`[data-action="${focused}"]`)?.focus({ preventScroll: true });
  }
  reply(m) { this.replyTo = m; $('reply-preview').hidden = !m; $('reply-text').textContent = m?.text.slice(0, 160) || ''; if (m) $('message-input').focus(); }
  search() {
    const query = $('message-search').value.trim().toLocaleLowerCase(); let count = 0;
    for (const m of this.messages.values()) { const match = !query || m.text.toLocaleLowerCase().includes(query); m.row.hidden = !match; if (match) count++; }
    $('search-result').textContent = query ? `${count} ${t('searchMatches')}` : '';
  }
  verify() { if (this.getSession()?.state !== 'connected') return; this.locallyVerifiedPeers.add(this.getSession()?.primary?.id || 'peer'); this.send({ k: 'verify', sas: this.getSession().verificationCode }); this.updateVerification(); }
  updateVerification() { const id = this.getSession()?.primary?.id || 'peer'; $('verify-peer').textContent = t(this.locallyVerifiedPeers.has(id) && this.verifiedPeers.has(id) ? 'mutuallyVerified' : this.locallyVerifiedPeers.has(id) ? 'verificationWaiting' : 'verifyMatched'); }
  setRoom(room) {
    for (const member of room.members) this.names.set(member.id, member.alias);
    for (const message of this.messages.values()) this.render(message);
    $('peer-name').textContent = room.members.length > 2 ? `${room.members.length} ${t('roomMembers')}` : room.members.find(m => m.id !== room.self)?.alias || '';
  }
  updateUnread() { $('jump-latest').hidden = this.unread === 0; $('jump-latest').textContent = `${this.unread} ${t('newMessages')}`; }
  snapshot() {
    const retained = [...this.messages.values()].filter(m => !m.ttl), ids = new Set(retained.map(m => m.id));
    return { version: 1, chatId: this.chatId, savedAt: Date.now(), alias: this.alias, peerAlias: this.peerAlias,
      messages: retained.map(({ id, text, mine, ts, replyTo, quote }) => ({ id, text, mine, ts, ...(ids.has(replyTo) ? { replyTo, quote } : {}) })) };
  }
  refresh() { for (const m of this.messages.values()) this.render(m); this.updateVerification(); this.search(); this.updateUnread(); }
  clear() {
    for (const timer of this.timers) clearTimeout(timer); this.timers.clear(); clearTimeout(this.typingTimer);
    this.messages.clear(); this.seenMessageIds.clear(); this.pendingReads.clear(); this.peerAlias = ''; this.localVerified = false; this.peerVerified = false; this.reply(null); this.unread = 0; this.updateUnread();
    this.names.clear(); this.verifiedPeers.clear(); this.locallyVerifiedPeers.clear();
    this.chatId = newId();
    $('typing-status').textContent = ''; $('peer-name').textContent = ''; $('message-search').value = ''; this.search();
  }
}
