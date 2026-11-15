import { PeerSession } from './peer.mjs';
import { MAX_ROOM_MEMBERS, newId, problem } from './protocol.mjs';

const RELAY = new Set(['meta', 'read', 'burn', 'react', 'typing', 'rename', 'receipt']);

// A room host terminates one encrypted channel per member and relays text.
// Files are deliberately sent only to the recipient selected by the sender.
export class RoomSession {
  constructor(callbacks) {
    this.callbacks = callbacks; this.state = 'idle'; this.hostId = newId(); this.selfId = this.hostId; this.isHost = true;
    this.peers = new Map(); this.filePeers = new Map(); this.roster = []; this.alias = ''; this.remoteHostId = null;
    this.primary = this._newPeer();
  }
  get verificationCode() { return this.primary?.peer.verificationCode || ''; }
  get sessionBinding() { return this.primary?.peer.sessionBinding || ''; }
  _state(state) { this.state = state; this.callbacks.onState?.(state); }
  _newPeer() {
    const record = { id: newId(), alias: '', peer: null };
    record.peer = new PeerSession({
      onState: state => {
        if (state === 'connected') {
          if (this.isHost) this._roster();
          this.callbacks.onPeerState?.(record.id, state);
        }
        if (state === 'closed') {
          this.peers.delete(record.id); this._roster();
          if (this.primary === record) this.primary = [...this.peers.values()].find(r => r.peer.state === 'connected') || record;
        }
        if (this.primary === record || !this.peers.size) this._state(state);
        else if (this.primary.peer.state === 'connected' && this.state !== 'connected') this._state('connected');
      },
      onMessage: frame => {
        const origin = this.isHost ? record.id : this.remoteHostId || record.id;
        this.callbacks.onMessage?.({ ...frame, origin, alias: record.alias });
        if (this.isHost) this._broadcast({ k: 'room-msg', id: frame.id, origin: record.id, alias: record.alias || 'Guest', text: frame.text }, record);
      },
      onControl: control => this._control(record, control),
      onTransfer: transfer => {
        this.filePeers.set(transfer.id, record);
        this.callbacks.onTransfer?.({ ...transfer, peerAlias: record.alias || 'Guest', peerId: record.id });
        if (this.filePeers.size > 200) {
          for (const [id, item] of this.filePeers) if (item.peer.incoming?.id !== id && item.peer.outgoing?.id !== id) { this.filePeers.delete(id); break; }
        }
      },
      onError: error => { if (record === this.primary || !this.peers.size) this.callbacks.onError?.(error); },
    });
    this.peers.set(record.id, record); return record;
  }
  _broadcast(control, except) { for (const r of this.peers.values()) if (r !== except && r.peer.state === 'connected') r.peer.sendControl(control); }
  _roster() {
    if (!this.isHost) return;
    const members = [{ id: this.hostId, alias: this.alias || 'Host' }, ...[...this.peers.values()].filter(r => r.peer.state === 'connected').map(r => ({ id: r.id, alias: r.alias || 'Guest' }))];
    this.roster = members;
    for (const r of this.peers.values()) if (r.peer.state === 'connected') r.peer.sendControl({ k: 'room-state', self: r.id, host: this.hostId, members });
    this.callbacks.onRoom?.({ members, self: this.hostId, host: this.hostId, isHost: true });
  }
  _control(record, c) {
    if (['identity', 'attestation', 'org-credential'].includes(c.k)) { this.callbacks.onEvidence?.(record, c); return; }
    if (c.k === 'verify') {
      this.callbacks.onControl?.({ ...c, linkId: record.id, linkSas: record.peer.verificationCode }); return;
    }
    if (this.isHost) {
      // A member cannot assert a roster or another member's author identity.
      if (c.k.startsWith('room-')) return;
      if (c.k === 'rename') { record.alias = c.alias; this._roster(); }
      this.callbacks.onControl?.({ ...c, origin: record.id });
      if (RELAY.has(c.k)) this._broadcast({ k: 'room-control', origin: record.id, control: c }, record);
      return;
    }
    if (c.k === 'room-state') {
      if (this.remoteHostId && this.remoteHostId !== c.host || this.selfId !== this.hostId && this.selfId !== c.self) throw problem('invalid-frame');
      this.selfId = c.self; this.remoteHostId = c.host; this.roster = c.members;
      record.alias = c.members.find(m => m.id === c.host)?.alias || record.alias;
      this.callbacks.onRoom?.({ ...c, isHost: false });
    } else if (c.k === 'room-msg') {
      if (!this.roster.some(m => m.id === c.origin) || c.origin === this.selfId) return;
      this.callbacks.onMessage?.({ id: c.id, text: c.text, origin: c.origin, alias: c.alias });
    } else if (c.k === 'room-control') {
      if (this.roster.some(m => m.id === c.origin) && c.origin !== this.selfId) this.callbacks.onControl?.({ ...c.control, origin: c.origin });
    } else this.callbacks.onControl?.({ ...c, origin: this.remoteHostId || record.id });
  }
  async createOffer() {
    if (this.state === 'connected') {
      if (!this.isHost || this.peers.size >= MAX_ROOM_MEMBERS - 1) throw problem('room-full');
      this.primary = this._newPeer();
    }
    return this.primary.peer.createOffer();
  }
  acceptOffer(code) { this.isHost = false; return this.primary.peer.acceptOffer(code); }
  acceptAnswer(code) { return this.primary.peer.acceptAnswer(code); }
  sendText(text) {
    const id = newId(); let sent = false;
    for (const r of this.peers.values()) if (r.peer.state === 'connected') { r.peer.sendText(text, id); sent = true; }
    if (!sent) throw problem('not-connected'); return id;
  }
  sendControl(control) {
    if (control.k === 'rename') this.alias = control.alias;
    if (control.k === 'verify') this.primary.peer.sendControl(control);
    else { this._broadcast(control); if (control.k === 'rename' && this.isHost) this._roster(); }
  }
  selectPeer(id) {
    const r = this.peers.get(id); if (!r || r.peer.state !== 'connected') return;
    this.primary = r; this._state('connected');
  }
  offerFile(file, recipient = this.primary?.id) {
    const record = this.peers.get(recipient);
    if (record?.peer.state !== 'connected') throw problem('not-connected');
    const id = record.peer.offerFile(file);
    this.callbacks.onFileOffered?.(record, id, file); return id;
  }
  acceptFile(id) { return this.filePeers.get(id)?.peer.acceptFile(id); }
  rejectFile(id) { return this.filePeers.get(id)?.peer.rejectFile(id); }
  cancelFile(id) { return this.filePeers.get(id)?.peer.cancelFile(id); }
  cancelInvitation() {
    if (this.primary?.peer.state === 'connected') return;
    const old = this.primary; this.primary = [...this.peers.values()].find(r => r.peer.state === 'connected') || old;
    old.peer.close(); this.peers.delete(old.id); if (this.primary.peer.state === 'connected') this._state('connected');
  }
  close() { this.callbacks = {}; for (const r of this.peers.values()) r.peer.close(); this.peers.clear(); this.filePeers.clear(); this.roster = []; this.state = 'closed'; }
}
