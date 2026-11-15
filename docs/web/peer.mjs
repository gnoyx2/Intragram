import { MAX_FILE_BYTES, MAX_TEXT_BYTES, MAX_INLINE_TEXT_BYTES, MAX_PART_BYTES, MAX_REASSEMBLED_BYTES, CHUNK_BYTES, problem, byteLength, newId,
  encodeDescription, decodeCode, parseFrame, makeChunk, parseChunk, validateControl } from './protocol.mjs';
export { MAX_FILE_BYTES, MAX_TEXT_BYTES, MAX_INLINE_TEXT_BYTES, decodeCode } from './protocol.mjs';

const ACTIVE = new Set(['offered', 'transferring']);
const BUFFER_LIMIT = 256 * 1024;

export class PeerSession {
  constructor(callbacks = {}) {
    this.callbacks = callbacks;
    this.state = 'idle';
    this.verificationCode = '';
    this.pc = null;
    this.channel = null;
    this.outgoing = null;
    this.incoming = null;
    this.waiters = new Set();
    this.seenMessages = new Set();
    this.parts = new Map();
  }

  _state(state) {
    if (this.state === state) return;
    this.state = state;
    this.callbacks.onState?.(state);
  }

  _prepare() {
    if (this.state !== 'idle') throw problem('session-in-use');
    if (typeof RTCPeerConnection === 'undefined' || !globalThis.crypto?.subtle) throw problem('unsupported-browser');
    const pc = new RTCPeerConnection({ iceServers: [], iceCandidatePoolSize: 0 });
    this.pc = pc;
    pc.ondatachannel = event => {
      if (this.channel || event.channel.label !== 'intragram-web-v1' ||
          !event.channel.ordered || event.channel.maxRetransmits !== null || event.channel.maxPacketLifeTime !== null) {
        event.channel.close();
        this._fail(problem('invalid-channel'));
        return;
      }
      this._attach(event.channel);
    };
    pc.onconnectionstatechange = () => {
      if (this.pc !== pc) return;
      clearTimeout(this.disconnectTimer);
      if (pc.connectionState === 'failed' || pc.connectionState === 'closed') this._fail(problem('connection-failed'));
      else if (pc.connectionState === 'disconnected') {
        this._state('disconnected');
        this.disconnectTimer = setTimeout(() => this._fail(problem('connection-failed')), 10000);
      } else if (pc.connectionState === 'connected' && this.channel?.readyState === 'open' && this.verificationCode) this._state('connected');
    };
    return pc;
  }

  async _description(pc) {
    if (pc.iceGatheringState !== 'complete') await new Promise((resolve, reject) => {
      const finish = error => {
        clearTimeout(timer);
        pc.removeEventListener('icegatheringstatechange', update);
        this.waiters.delete(cancel);
        error ? reject(error) : resolve();
      };
      const update = () => { if (pc.iceGatheringState === 'complete') finish(); };
      const cancel = () => finish(problem('session-closed'));
      const timer = setTimeout(() => finish(problem('ice-timeout')), 12000);
      this.waiters.add(cancel);
      pc.addEventListener('icegatheringstatechange', update);
      update();
    });
    if (this.pc !== pc) throw problem('session-closed');
    return encodeDescription(pc.localDescription);
  }

  async createOffer() {
    const pc = this._prepare();
    this._state('gathering');
    try {
      this._attach(pc.createDataChannel('intragram-web-v1', { ordered: true }));
      await pc.setLocalDescription(await pc.createOffer());
      const code = await this._description(pc);
      this._state('waiting');
      return code;
    } catch (error) { this.close(); throw error; }
  }

  async acceptOffer(code) {
    const offer = decodeCode(code, 'offer');
    const pc = this._prepare();
    this._state('gathering');
    try {
      await pc.setRemoteDescription(offer);
      await pc.setLocalDescription(await pc.createAnswer());
      const answer = await this._description(pc);
      this._state('connecting');
      this._connectionDeadline();
      return answer;
    } catch (error) { this.close(); throw error; }
  }

  async acceptAnswer(code) {
    const answer = decodeCode(code, 'answer');
    if (this.state !== 'waiting' || !this.pc) throw problem('unexpected-answer');
    try {
      this._state('connecting');
      await this.pc.setRemoteDescription(answer);
      this._connectionDeadline();
    } catch (error) { this.close(); throw error; }
  }

  _connectionDeadline() {
    clearTimeout(this.connectTimer);
    if (this.state !== 'connected') this.connectTimer = setTimeout(() => this._fail(problem('connection-timeout')), 120000);
  }

  _attach(channel) {
    this.channel = channel;
    channel.binaryType = 'arraybuffer';
    channel.bufferedAmountLowThreshold = BUFFER_LIMIT / 2;
    channel.onopen = () => {
      clearTimeout(this.connectTimer);
      this._fingerprint().then(() => {
        if (this.channel === channel && channel.readyState === 'open') this._state('connected');
      }).catch(error => this._fail(error));
    };
    channel.onclose = () => { if (this.channel === channel) this._fail(problem('connection-closed')); };
    channel.onerror = () => { if (this.channel === channel) this._fail(problem('connection-failed')); };
    channel.onmessage = event => {
      if (this.channel !== channel) return;
      try { this._receive(event.data); } catch (error) { this._fail(error); }
    };
  }

  async _fingerprint() {
    const pc = this.pc;
    const fingerprints = [pc.localDescription, pc.remoteDescription].map(description => {
      const match = /^a=fingerprint:sha-256 (.+)$/im.exec(description?.sdp || '');
      if (!match) throw problem('invalid-code');
      return match[1].trim().toUpperCase();
    }).sort().join('|');
    const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(fingerprints));
    if (this.pc !== pc) return;
    this.sessionBinding = btoa(Array.from(new Uint8Array(hash), b => String.fromCharCode(b)).join(''));
    this.verificationCode = String(new DataView(hash).getUint32(0) % 1000000).padStart(6, '0');
  }

  _send(frame) {
    if (this.state !== 'connected' || this.channel?.readyState !== 'open') throw problem('not-connected');
    if (this.channel.bufferedAmount > BUFFER_LIMIT * 4) throw problem('send-busy');
    this.channel.send(JSON.stringify(frame));
  }

  sendText(text, id = newId()) {
    if (typeof text !== 'string' || !text.trim() || byteLength(text) > MAX_TEXT_BYTES) throw problem('text-too-large');
    const frame = { kind: 'text', id, text };
    try { parseFrame(JSON.stringify(frame)); } catch { throw problem('text-too-large'); }
    this._send(frame);
    return id;
  }

  sendControl(control) {
    validateControl(control);
    this._send({ kind: 'control', id: newId(), control });
  }

  offerFile(file) {
    if (!file || typeof file.slice !== 'function' || typeof file.name !== 'string') throw problem('invalid-file');
    if (ACTIVE.has(this.outgoing?.state)) throw problem('transfer-busy');
    const frame = { kind: 'file-offer', id: newId(), name: file.name, size: file.size };
    try { parseFrame(JSON.stringify(frame)); } catch { throw problem('invalid-file'); }
    this._send(frame);
    this.outgoing = { ...frame, file, direction: 'send', state: 'offered', transferred: 0 };
    this._transfer(this.outgoing);
    return frame.id;
  }

  acceptFile(id) {
    const transfer = this.incoming;
    if (transfer?.id !== id || transfer.state !== 'offered') throw problem('unknown-transfer');
    this._send({ kind: 'file-accept', id });
    transfer.state = 'transferring';
    transfer.chunks = [];
    this._transfer(transfer);
    this._transferDeadline(transfer);
  }

  rejectFile(id) {
    const transfer = this.incoming;
    if (transfer?.id !== id || transfer.state !== 'offered') return;
    this._send({ kind: 'file-reject', id });
    this._finish(transfer, 'rejected');
  }

  cancelFile(id) {
    const transfer = [this.incoming, this.outgoing].find(t => t?.id === id && ACTIVE.has(t.state));
    if (!transfer) return;
    try { this._send({ kind: 'file-cancel', id }); } finally { this._finish(transfer, 'cancelled'); }
  }

  _transfer(transfer, blob) {
    this.callbacks.onTransfer?.({ id: transfer.id, direction: transfer.direction, name: transfer.name,
      size: transfer.size, state: transfer.state, transferred: transfer.transferred, ...(blob ? { blob } : {}) });
  }

  _finish(transfer, state, blob) {
    clearTimeout(transfer.timer);
    transfer.state = state;
    transfer.chunks = null;
    transfer.file = null;
    this._transfer(transfer, blob);
  }

  _transferDeadline(transfer) {
    clearTimeout(transfer.timer);
    if (!ACTIVE.has(transfer.state)) return;
    transfer.timer = setTimeout(() => {
      if (!ACTIVE.has(transfer.state)) return;
      try { this._send({ kind: 'file-cancel', id: transfer.id }); } catch {}
      this._finish(transfer, 'failed');
    }, 30000);
  }

  _receive(data) {
    if (typeof data !== 'string') {
      const chunk = parseChunk(data);
      const transfer = this.incoming;
      if (transfer?.id !== chunk.id || transfer.state !== 'transferring') return;
      if (chunk.offset !== transfer.transferred || transfer.transferred + chunk.bytes.byteLength > transfer.size) throw problem('invalid-file-data');
      transfer.chunks.push(chunk.bytes);
      transfer.transferred += chunk.bytes.byteLength;
      this._transfer(transfer);
      this._transferDeadline(transfer);
      return;
    }
    const frame = parseFrame(data);
    const incoming = this.incoming;
    const outgoing = this.outgoing;
    if (frame.kind === 'text') {
      if (this.seenMessages.has(frame.id)) return;
      this.seenMessages.add(frame.id);
      if (this.seenMessages.size > 1000) this.seenMessages.delete(this.seenMessages.values().next().value);
      this.callbacks.onMessage?.({ id: frame.id, text: frame.text });
    } else if (frame.kind === 'control') {
      this.callbacks.onControl?.(frame.control);
    } else if (frame.kind === 'part') {
      this._receivePart(frame);
    } else if (frame.kind === 'file-offer') {
      if (incoming?.id === frame.id) return;
      if (ACTIVE.has(incoming?.state)) { this._send({ kind: 'file-reject', id: frame.id }); return; }
      this.incoming = { ...frame, direction: 'receive', state: 'offered', transferred: 0 };
      this._transfer(this.incoming);
    } else if (frame.kind === 'file-cancel') {
      for (const transfer of [incoming, outgoing]) if (transfer?.id === frame.id && ACTIVE.has(transfer.state)) this._finish(transfer, 'cancelled');
    } else if (frame.kind === 'file-reject' && outgoing?.id === frame.id && outgoing.state === 'offered') {
      this._finish(outgoing, 'rejected');
    } else if (frame.kind === 'file-accept' && outgoing?.id === frame.id && outgoing.state === 'offered') {
      outgoing.state = 'transferring';
      this._transfer(outgoing);
      this._stream(outgoing).catch(error => {
        if (!ACTIVE.has(outgoing.state)) return;
        try { this._send({ kind: 'file-cancel', id: outgoing.id }); } catch {}
        this._finish(outgoing, 'failed');
        this.callbacks.onError?.(error);
      });
    } else if (frame.kind === 'file-end' && incoming?.id === frame.id && incoming.state === 'transferring') {
      if (incoming.transferred !== incoming.size) throw problem('incomplete-file');
      const blob = new Blob(incoming.chunks, { type: 'application/octet-stream' });
      this._send({ kind: 'file-done', id: incoming.id });
      this._finish(incoming, 'complete', blob);
    } else if (frame.kind === 'file-done' && outgoing?.id === frame.id && outgoing.state === 'transferring') {
      if (!outgoing.ended || outgoing.transferred !== outgoing.size) throw problem('invalid-file-receipt');
      this._finish(outgoing, 'complete');
    }
  }

  async _backpressure() {
    const channel = this.channel;
    if (channel?.readyState !== 'open') throw problem('not-connected');
    if (channel.bufferedAmount <= BUFFER_LIMIT) return;
    await new Promise((resolve, reject) => {
      const finish = error => {
        clearTimeout(timer);
        channel.removeEventListener('bufferedamountlow', ready);
        this.waiters.delete(cancel);
        error ? reject(error) : resolve();
      };
      const ready = () => finish();
      const cancel = () => finish(problem('session-closed'));
      const timer = setTimeout(() => finish(problem('transfer-timeout')), 30000);
      this.waiters.add(cancel);
      channel.addEventListener('bufferedamountlow', ready, { once: true });
      if (channel.bufferedAmount <= channel.bufferedAmountLowThreshold) finish();
    });
  }

  async _stream(transfer) {
    while (transfer.transferred < transfer.size && transfer.state === 'transferring') {
      await this._backpressure();
      if (transfer.state !== 'transferring') return;
      const bytes = await transfer.file.slice(transfer.transferred, transfer.transferred + CHUNK_BYTES).arrayBuffer();
      if (transfer.state !== 'transferring') return;
      if (!bytes.byteLength) throw problem('invalid-file-data');
      this.channel.send(makeChunk(transfer.id, transfer.transferred, bytes));
      transfer.transferred += bytes.byteLength;
      this._transfer(transfer);
    }
    if (transfer.state !== 'transferring') return;
    await this._backpressure();
    if (transfer.state !== 'transferring') return;
    transfer.ended = true;
    this._send({ kind: 'file-end', id: transfer.id });
    this._transferDeadline(transfer);
  }

  _receivePart(frame) {
    if (this.seenMessages.has(frame.id)) return;
    const raw = Uint8Array.from(atob(frame.data), c => c.charCodeAt(0));
    let totalHeld = 0;
    for (const item of this.parts.values()) totalHeld += item.received;
    if (totalHeld + raw.byteLength > MAX_REASSEMBLED_BYTES) throw problem('invalid-frame');
    let entry = this.parts.get(frame.id);
    if (frame.index === 0) {
      if (entry || this.parts.size >= 4) throw problem('invalid-frame');
      entry = { target: frame.target, count: frame.count, total: frame.total, next: 0, received: 0, chunks: [], timer: null };
      this.parts.set(frame.id, entry);
    } else if (!entry || entry.target !== frame.target || entry.count !== frame.count || entry.total !== frame.total || entry.next !== frame.index) {
      throw problem('invalid-frame');
    }
    if (entry.received + raw.byteLength > frame.total) { clearTimeout(entry.timer); this.parts.delete(frame.id); throw problem('invalid-frame'); }
    entry.chunks.push(raw);
    entry.received += raw.byteLength;
    entry.next = frame.index + 1;
    clearTimeout(entry.timer);
    entry.timer = setTimeout(() => this.parts.delete(frame.id), 30000);
    if (entry.next < entry.count) return;
    clearTimeout(entry.timer);
    this.parts.delete(frame.id);
    if (entry.received !== entry.total) throw problem('invalid-frame');
    const merged = new Uint8Array(entry.total);
    let offset = 0;
    for (const part of entry.chunks) { merged.set(part, offset); offset += part.byteLength; }
    let decoded;
    try { decoded = new TextDecoder('utf-8', { fatal: true }).decode(merged); } catch { throw problem('invalid-frame'); }
    if (frame.target === 'text') {
      if (!decoded.trim() || merged.byteLength > MAX_INLINE_TEXT_BYTES) throw problem('invalid-frame');
      this.seenMessages.add(frame.id);
      if (this.seenMessages.size > 1000) this.seenMessages.delete(this.seenMessages.values().next().value);
      this.callbacks.onMessage?.({ id: frame.id, text: decoded });
      return;
    }
    let control;
    try { control = JSON.parse(decoded); } catch { throw problem('invalid-frame'); }
    validateControl(control, MAX_INLINE_TEXT_BYTES);
    this.callbacks.onControl?.(control);
  }

  _fail(error) {
    if (this.state === 'closed') return;
    this.close();
    this.callbacks.onError?.(error);
  }

  close() {
    if (this.state === 'closed') return;
    clearTimeout(this.connectTimer);
    clearTimeout(this.disconnectTimer);
    for (const entry of this.parts.values()) clearTimeout(entry.timer);
    this.parts.clear();
    const channel = this.channel, pc = this.pc;
    this.channel = null;
    this.pc = null;
    for (const cancel of this.waiters) cancel();
    for (const transfer of [this.incoming, this.outgoing]) if (transfer && ACTIVE.has(transfer.state)) this._finish(transfer, 'failed');
    channel?.close();
    pc?.close();
    this.seenMessages.clear();
    this.verificationCode = '';
    this._state('closed');
  }
}
