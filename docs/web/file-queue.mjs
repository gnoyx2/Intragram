import { MAX_FILE_BYTES, problem } from './protocol.mjs';
import { t } from './i18n.mjs';

export class FileQueue {
  constructor({ getSession, onError }) {
    this.getSession = getSession; this.onError = onError; this.pending = []; this.active = null; this.epoch = 0;
    document.getElementById('cancel-file-queue').onclick = () => {
      const active = this.active; this.clear(); if (active) this.getSession()?.cancelFile(active);
    };
  }
  add(files) {
    const session = this.getSession();
    if (session?.state !== 'connected') throw problem('not-connected');
    if (!files.length || files.length + this.pending.length > 100) throw problem('file-queue-full');
    if (files.some(file => file.size > MAX_FILE_BYTES || !file.name || file.name.length > 255 || /[\x00-\x1f\x7f/\\]/.test(file.name))) throw problem('invalid-file');
    for (const file of files) this.pending.push({ file, recipient: session.primary?.id });
    this.advance(); this.refresh();
  }
  advance() {
    if (this.active || !this.pending.length) return;
    const session = this.getSession();
    if (session?.state !== 'connected') return;
    const item = this.pending.shift();
    if (!session.peers.get(item.recipient) || session.peers.get(item.recipient).peer.state !== 'connected') { this.onError(problem('not-connected')); this.advance(); return; }
    try { this.active = session.offerFile(item.file, item.recipient); }
    catch (error) { this.onError(error); this.advance(); }
    this.refresh();
  }
  transfer(transfer) {
    if (transfer.id !== this.active || ['offered', 'transferring'].includes(transfer.state)) return;
    this.active = null; const epoch = this.epoch;
    queueMicrotask(() => { if (this.epoch === epoch) this.advance(); }); this.refresh();
  }
  refresh() {
    document.getElementById('file-queue-status').textContent = this.pending.length ? `${this.pending.length} ${t('queuedFiles')}` : '';
    document.getElementById('cancel-file-queue').hidden = !this.pending.length;
  }
  clear() { this.epoch++; this.pending = []; this.active = null; this.refresh(); }
}
