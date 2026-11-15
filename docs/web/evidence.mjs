import { bytes, b64, encode, hash, random, hex, verify, sign, peerId, fail, attestationBytes, verifyAttestation, credential, credentialBytes } from './evidence-wire.mjs';
import { parseTrustBundle, presentOrganization, checkOrganization } from './evidence-org.mjs';
import { exportEvidenceBundle, verifyEvidenceBundle, witnessEvidenceBundle, verifyAnchor } from './evidence-bundle.mjs';
export { validateEvidenceControl } from './evidence-wire.mjs';
// One ephemeral application identity can be shared by independent DTLS links.
export class WebPeerIdentity {
  constructor() { this.generation = 0; }
  async ready() {
    if (!this.creating) {
      const generation = this.generation;
      this.creating = (async () => {
        const keys = await crypto.subtle.generateKey('Ed25519', false, ['sign', 'verify']);
        const raw = new Uint8Array(await crypto.subtle.exportKey('raw', keys.publicKey));
        const id = await peerId(raw);
        if (generation !== this.generation) fail();
        this.keys = keys; this.publicKey = b64(raw); this.peerId = id;
      })();
    }
    await this.creating;
  }
  clear() { this.generation++; this.keys = null; this.publicKey = null; this.peerId = null; this.creating = null; }
}
export class WebPeerEvidence {
  constructor({ sendControl, onChange, alias = 'Web', identity = new WebPeerIdentity() }) {
    this.sendControl = sendControl; this.onChange = onChange; this.alias = alias;
    this.identity = identity;
    this.entries = []; this.expectedFiles = new Map(); this.peerIdentity = null;
    this.binding = ''; this.generation = 0; this.nextBatch = 1; this.organization = null;
    this.queue = Promise.resolve(); this.queued = 0; this.lastBundle = null; this.revision = 0;
  }
  get keys() { return this.identity.keys; }
  get publicKey() { return this.identity.publicKey; }
  get peerId() { return this.identity.peerId; }
  async ready() { await this.identity.ready(); }
  async start(binding, { dialled = true } = {}) {
    const generation = this.generation;
    bytes(binding, 32);
    if (this.binding && (this.binding !== binding || this.dialled !== dialled)) fail();
    this.binding = binding; this.dialled = dialled;
    await this.ready();
    if (generation !== this.generation) return;
    const signature = await sign(this.keys.privateKey, encode(['intragram/web-identity/v1', binding, this.publicKey]));
    if (generation !== this.generation) return;
    await this.sendControl({ k: 'identity', pk: this.publicKey, sg: b64(signature) });
  }
  receive(control) {
    if (this.queued >= 32) return Promise.resolve();
    const generation = this.generation; this.queued++;
    const operation = this.queue.then(() => generation === this.generation ? this._receive(control) : undefined);
    this.queue = operation.catch(() => {}).finally(() => { this.queued--; });
    return operation;
  }
  async _receive(control) {
    if (!this.binding) return;
    const generation = this.generation;
    await this.ready();
    if (generation !== this.generation) return;
    if (control.k === 'identity') {
      const key = bytes(control.pk, 32);
      if (b64(key) === this.publicKey) return;
      if (!await verify(key, bytes(control.sg, 64), encode(['intragram/web-identity/v1', this.binding, control.pk]))) return;
      const id = await peerId(key);
      if (generation !== this.generation || this.peerIdentity && this.peerIdentity.peerId !== id) return;
      this.peerIdentity = { peerId: id, publicKey: control.pk, key };
      await this.presentCredential();
    } else if (control.k === 'attestation') {
      const a = control.value;
      if (!this.peerIdentity || await peerId(bytes(a.pk, 32)) !== this.peerIdentity.peerId ||
          a.a !== this.binding.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '') ||
          a.cp !== this.peerId || a.ck !== this.publicKey || !await verifyAttestation(a)) return;
      if (generation !== this.generation) return;
      const expected = this.expectedFiles.get(a.s);
      const status = a.k !== 'deliveryCommitted' ? 'verified' : expected == null ? 'unbound' : (await expected) === a.c ? 'verified' : 'rejected';
      if (generation !== this.generation) return;
      this._add(a, status);
    } else if (control.k === 'org-credential') await checkOrganization(this, control);
    if (generation === this.generation) { this._scheduleOrganizationExpiry(); this.onChange?.(); }
  }
  async expectFile(id, value) {
    const generation = this.generation;
    const digest = hash(value).then(b64);
    this.expectedFiles.set(id, digest);
    if (this.expectedFiles.size > 512) this.expectedFiles.delete(this.expectedFiles.keys().next().value);
    const expected = await digest;
    if (generation !== this.generation) return;
    for (const entry of this.entries) if (entry.attestation.s === id && entry.status === 'unbound') { entry.status = expected === entry.attestation.c ? 'verified' : 'rejected'; this.revision++; }
    this.onChange?.();
  }
  async recordFile(id, value) { await this._issue('deliveryCommitted', id, b64(await hash(value)), 'delivery/web-ram', 'buffered'); }
  async recordBurn(id, text) { await this._issue('burnTriggered', id, b64(await hash(new Uint8Array([...random(16), ...encode(['intragram/web-burn/v1', id, text])]))), 'burn/web-memory', 'triggered'); }
  async _issue(kind, id, commitment, policy, outcome) {
    if (!this.binding || !this.peerIdentity) return;
    const generation = this.generation;
    const a = { domain: 'intragram/attestation/v1', k: kind, e: hex(random(12)), s: id,
      a: this.binding.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', ''), pk: this.publicKey,
      cp: this.peerIdentity.peerId, ck: this.peerIdentity.publicKey, c: commitment, p: policy, o: outcome, n: b64(random(16)), t: Date.now() };
    a.sg = b64(await sign(this.keys.privateKey, attestationBytes({ ...a, sg: b64(new Uint8Array(64)) })));
    if (generation !== this.generation) return;
    this._add(a, 'issued'); await this.sendControl({ k: 'attestation', value: a });
    if (generation === this.generation) this.onChange?.();
  }
  _add(a, status) {
    if (this.entries.some(e => e.attestation.e === a.e)) return;
    this.entries.push({ attestation: a, status, salt: b64(random(16)) });
    this.revision++;
    if (this.entries.length > 512) this.entries.shift();
  }
  async exportBundle() { await this.ready(); return exportEvidenceBundle(this); }
  async importBundle(text) { return verifyEvidenceBundle(text); }
  async witnessBundle(text) { await this.ready(); return witnessEvidenceBundle(this, text); }
  async attachAnchor(text, witness) {
    try { if (typeof text !== 'string' || text.length > 4096) return false;
      const a = JSON.parse(text), bundle = this.lastBundle;
      if (!bundle || !witness || !await verifyAnchor(a, bundle.batch, witness) || this.lastBundle !== bundle) return false;
      bundle.anchor = a; return true; } catch { return false; }
  }
  async setTrustBundle(raw) {
    this.trust = parseTrustBundle(raw);
    if (this.presentation) await checkOrganization(this, this.presentation);
    this._scheduleOrganizationExpiry(); this.onChange?.();
  }
  async setCredential(raw) {
    if (typeof raw !== 'string' || raw.length > 8192) fail();
    await this.ready(); const c = credential(JSON.parse(raw));
    if (c.sk !== this.publicKey || !await verify(bytes(c.ik, 32), bytes(c.sg, 64), credentialBytes(c)) || Date.now() >= c.exp) fail();
    this.credential = c; this._scheduleOrganizationExpiry(); await this.presentCredential(); this.onChange?.();
  }
  async presentCredential() { await presentOrganization(this); }
  _scheduleOrganizationExpiry() {
    clearTimeout(this.expiryTimer);
    const now = Date.now();
    if (this.credential && this.credential.exp <= now) {
      this.credential = null;
      if (this.binding) Promise.resolve(this.sendControl({ k: 'org-credential' })).catch(() => {});
    }
    if (this.organization?.verified && this.organization.credential.exp <= now) this.organization = { ...this.organization, check: 'expired', verified: false };
    const deadlines = [this.credential?.exp, this.organization?.verified ? this.organization.credential.exp : undefined].filter(v => v !== undefined);
    if (deadlines.length) this.expiryTimer = setTimeout(() => { this._scheduleOrganizationExpiry(); this.onChange?.(); }, Math.min(2147483647, Math.max(0, Math.min(...deadlines) - now)));
  }
  clear() {
    clearTimeout(this.expiryTimer);
    this.generation++; this.revision++; this.binding = ''; this.entries = []; this.expectedFiles.clear(); this.peerIdentity = null;
    this.credential = null; this.presentation = null; this.organization = null; this.lastBundle = null; this.onChange?.();
  }
}
