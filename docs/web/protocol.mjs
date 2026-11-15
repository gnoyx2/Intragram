export const MAX_FILE_BYTES = 100 * 1024 * 1024;
export const MAX_TEXT_BYTES = 16 * 1024;
export const MAX_INLINE_TEXT_BYTES = 1024 * 1024;
export const MAX_PART_BYTES = 12 * 1024;
export const MAX_REASSEMBLED_BYTES = MAX_INLINE_TEXT_BYTES * 2 + 8192;
export const MAX_ROOM_MEMBERS = 32;
export const MAX_CODE_CHARS = 48 * 1024;
export const CHUNK_BYTES = 16 * 1024;
const encoder = new TextEncoder();
const ID = /^[a-f0-9]{32}$/;

export function problem(code) { return Object.assign(new Error(code), { code }); }
export function byteLength(text) { return encoder.encode(text).byteLength; }
export function newId() {
  return Array.from(crypto.getRandomValues(new Uint8Array(16)), b => b.toString(16).padStart(2, '0')).join('');
}

export function localAddress(host) {
  if (/^[a-z0-9-]+(?:\.[a-z0-9-]+)*\.local$/i.test(host) && host.length <= 253) return true;
  if (host.includes(':')) {
    try { new URL(`http://[${host}]/`); } catch { return false; }
    return host === '::1' || /^f[cd][a-f0-9]{2}:/i.test(host) || /^fe[89ab][a-f0-9]:/i.test(host);
  }
  const parts = host.split('.');
  if (parts.length !== 4 || parts.some(p => !/^(0|[1-9]\d{0,2})$/.test(p) || Number(p) > 255)) return false;
  const [a, b] = parts.map(Number);
  return a === 10 || a === 127 || (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168) || (a === 169 && b === 254);
}

function validCandidate(line) {
  const p = line.trim().split(/\s+/);
  return p.length >= 8 && /^a=candidate:[\w+/.-]+$/.test(p[0]) && p[1] === '1' &&
    /^(udp|tcp)$/i.test(p[2]) && /^\d+$/.test(p[3]) && localAddress(p[4]) &&
    /^\d+$/.test(p[5]) && Number(p[5]) > 0 && Number(p[5]) <= 65535 &&
    p[6] === 'typ' && p[7] === 'host' && !p.includes('raddr') && !p.includes('rport');
}

export function validateDescription(description, expectedType) {
  if (!description || typeof description !== 'object' || description.type !== expectedType ||
      !['offer', 'answer'].includes(description.type) || typeof description.sdp !== 'string' ||
      description.sdp.length > 32000 || /[^\x09\x0a\x0d\x20-\x7e]/.test(description.sdp)) throw problem('invalid-code');
  const lines = description.sdp.trim().split(/\r?\n/);
  const media = lines.filter(l => l.startsWith('m='));
  const candidates = lines.filter(l => l.startsWith('a=candidate:'));
  const fingerprints = lines.filter(l => /^a=fingerprint:/i.test(l));
  if (lines[0] !== 'v=0' || media.length !== 1 ||
      lines.some(l => !/^[a-z]=/.test(l)) ||
      !/^m=application \d+ UDP\/DTLS\/SCTP webrtc-datachannel$/.test(media[0]) ||
      fingerprints.length !== 1 || !/^a=fingerprint:sha-256 (?:[a-f\d]{2}:){31}[a-f\d]{2}$/i.test(fingerprints[0]) ||
      lines.filter(l => /^a=ice-ufrag:/i.test(l)).length !== 1 ||
      lines.filter(l => /^a=ice-pwd:/i.test(l)).length !== 1 ||
      !lines.some(l => /^a=ice-ufrag:[a-z\d+/]{4,256}$/i.test(l)) ||
      !lines.some(l => /^a=ice-pwd:[a-z\d+/]{22,256}$/i.test(l)) ||
      !candidates.length || candidates.some(l => !validCandidate(l)) ||
      lines.some(l => /^a=(?:remote-candidates|ice-lite)/.test(l))) throw problem('invalid-code');
  return { type: description.type, sdp: description.sdp };
}

export function encodeDescription(description) {
  // Host candidates only: never exchange a public address learned from an interface or VPN.
  const sdp = description.sdp.split(/\r?\n/).filter(l => !l.startsWith('a=candidate:') || validCandidate(l)).join('\r\n');
  const clean = validateDescription({ type: description.type, sdp }, description.type);
  const bytes = encoder.encode(JSON.stringify({ v: 1, ...clean }));
  const base64 = btoa(Array.from(bytes, b => String.fromCharCode(b)).join(''));
  return 'IGW1.' + base64.replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

export function decodeCode(raw, expectedType) {
  if (typeof raw !== 'string' || raw.length > MAX_CODE_CHARS) throw problem('invalid-code');
  const code = raw.trim();
  if (!/^IGW1\.[a-z\d_-]+$/i.test(code)) throw problem('invalid-code');
  let data;
  try {
    const text = atob(code.slice(5).replaceAll('-', '+').replaceAll('_', '/'));
    data = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Uint8Array.from(text, c => c.charCodeAt(0))));
  } catch { throw problem('invalid-code'); }
  if (data?.v !== 1) throw problem('invalid-code');
  return validateDescription(data, expectedType || data.type);
}

export function parseFrame(raw) {
  if (typeof raw !== 'string' || byteLength(raw) > MAX_TEXT_BYTES + 512) throw problem('invalid-frame');
  let frame;
  try { frame = JSON.parse(raw); } catch { throw problem('invalid-frame'); }
  if (!frame || typeof frame !== 'object' || !ID.test(frame.id) || typeof frame.kind !== 'string') throw problem('invalid-frame');
  if (frame.kind === 'text') {
    if (typeof frame.text !== 'string' || !frame.text.trim() || byteLength(frame.text) > MAX_TEXT_BYTES) throw problem('invalid-frame');
  } else if (frame.kind === 'file-offer') {
    if (typeof frame.name !== 'string' || !frame.name || frame.name.length > 255 || /[\x00-\x1f\x7f/\\]/.test(frame.name) ||
        frame.stream !== undefined && typeof frame.stream !== 'boolean' ||
        !Number.isSafeInteger(frame.size) || frame.size < 0 || frame.size > MAX_FILE_BYTES ||
        frame.origin !== undefined && !ID.test(frame.origin) ||
        frame.alias !== undefined && (typeof frame.alias !== 'string' || !frame.alias.trim() || frame.alias.length > 80 || /[\x00-\x1f\x7f]/.test(frame.alias))) throw problem('invalid-frame');
  } else if (frame.kind === 'control') {
    validateControl(frame.control);
  } else if (frame.kind === 'part') {
    const maxCount = Math.floor(MAX_REASSEMBLED_BYTES / MAX_PART_BYTES) + 2;
    if (!['text', 'control'].includes(frame.target) ||
        !Number.isSafeInteger(frame.index) || !Number.isSafeInteger(frame.count) || !Number.isSafeInteger(frame.total) ||
        frame.count < 2 || frame.count > maxCount || frame.index < 0 || frame.index >= frame.count ||
        frame.total <= 0 || frame.total > MAX_REASSEMBLED_BYTES ||
        typeof frame.data !== 'string' || !frame.data || frame.data.length > 16384 || !/^[A-Za-z0-9+/]+=*$/.test(frame.data)) throw problem('invalid-frame');
    let decoded;
    try { decoded = atob(frame.data); } catch { throw problem('invalid-frame'); }
    if (!decoded.length || decoded.length > MAX_PART_BYTES || decoded.length > frame.total) throw problem('invalid-frame');
  } else if (!['file-accept', 'file-reject', 'file-cancel', 'file-end', 'file-done'].includes(frame.kind)) {
    throw problem('invalid-frame');
  }
  return frame;
}

export function makeChunk(id, offset, bytes) {
  const result = new Uint8Array(20 + bytes.byteLength);
  for (let i = 0; i < 16; i++) result[i] = parseInt(id.slice(i * 2, i * 2 + 2), 16);
  new DataView(result.buffer).setUint32(16, offset);
  result.set(new Uint8Array(bytes), 20);
  return result.buffer;
}

export function parseChunk(buffer) {
  if (!(buffer instanceof ArrayBuffer) || buffer.byteLength <= 20 || buffer.byteLength > CHUNK_BYTES + 20) throw problem('invalid-frame');
  const bytes = new Uint8Array(buffer);
  return {
    id: Array.from(bytes.subarray(0, 16), b => b.toString(16).padStart(2, '0')).join(''),
    offset: new DataView(buffer).getUint32(16),
    bytes: buffer.slice(20),
  };
}


export const REACTIONS = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
export const TTL_VALUES = [0, 5, 10, 30, 60, 300, 3600, 86400];
export function validateControl(c, maxTextBytes = MAX_TEXT_BYTES) {
  const fail = () => { throw problem('invalid-frame'); };
  if (!c || typeof c !== 'object' || Array.isArray(c)) fail();
  const ref = () => { if (!ID.test(c.id)) fail(); };
  switch (c.k) {
    case 'typing': if (typeof c.on !== 'boolean') fail(); break;
    case 'read': case 'burn': case 'receipt': ref(); break;
    case 'react': ref(); if (!REACTIONS.includes(c.emoji) || typeof c.on !== 'boolean') fail(); break;
    case 'rename': if (typeof c.alias !== 'string' || !c.alias.trim() || c.alias.length > 80 || /[\x00-\x1f\x7f]/.test(c.alias)) fail(); break;
    case 'meta':
      ref();
      if (!TTL_VALUES.includes(c.ttl) || c.replyTo !== undefined && !ID.test(c.replyTo) || c.quote !== undefined && (typeof c.quote !== 'string' || c.quote.length > 500)) fail();
      break;
    case 'verify': if (typeof c.sas !== 'string' || !/^\d{6}$/.test(c.sas)) fail(); break;
    case 'identity': case 'attestation': case 'org-credential': validateEvidenceControl(c); break;
    case 'native-room': {
      // Opaque native capability/room frames are ignored by the HTML fallback.
      // Native Flutter peers validate their signed v7 contents separately.
      const frame = c.frame;
      if (!frame || typeof frame !== 'object' || Array.isArray(frame) || !['capabilities', 'msg', 'room_state'].includes(frame.k) ||
          frame.k === 'capabilities' && frame.v !== 1 ||
          c.origin !== undefined && !ID.test(c.origin) ||
          c.alias !== undefined && (typeof c.alias !== 'string' || !c.alias.trim() || c.alias.length > 80 || /[\x00-\x1f\x7f]/.test(c.alias))) fail();
      const maxNativeBytes = maxTextBytes <= MAX_TEXT_BYTES ? 8192 : MAX_REASSEMBLED_BYTES;
      try { if (byteLength(JSON.stringify(frame)) > maxNativeBytes) fail(); } catch { fail(); }
      break;
    }
    case 'room-state': {
      if (!ID.test(c.self) || !ID.test(c.host) || !Array.isArray(c.members) || c.members.length < 1 || c.members.length > MAX_ROOM_MEMBERS) fail();
      const ids = new Set();
      for (const m of c.members) {
        if (!m || !ID.test(m.id) || typeof m.alias !== 'string' || !m.alias.trim() || m.alias.length > 80 || /[\x00-\x1f\x7f]/.test(m.alias) || ids.has(m.id)) fail();
        ids.add(m.id);
      }
      if (!ids.has(c.self) || !ids.has(c.host)) fail();
      break;
    }
    case 'room-msg':
      ref(); if (!ID.test(c.origin) || typeof c.alias !== 'string' || !c.alias.trim() || c.alias.length > 80 || /[\x00-\x1f\x7f]/.test(c.alias) || typeof c.text !== 'string' || !c.text.trim() || byteLength(c.text) > maxTextBytes) fail();
      break;
    case 'room-control':
      if (!ID.test(c.origin) || !['meta', 'read', 'burn', 'react', 'typing', 'rename', 'receipt'].includes(c.control?.k)) fail();
      validateControl(c.control); break;
    default: fail();
  }
  return c;
}
import { validateEvidenceControl } from './evidence-wire.mjs';
