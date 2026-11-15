import { WebPeerEvidence, WebPeerIdentity } from './evidence.mjs';
import { t } from './i18n.mjs';

const el = (tag, text) => { const node = document.createElement(tag); if (text) node.textContent = text; return node; };
export class EvidenceExperience {
  constructor({ getSession, onError }) {
    this.getSession = getSession; this.onError = onError; this.peers = new Map(); this.pending = new Map(); this.epoch = 0;
    this.appIdentity = new WebPeerIdentity();
    this.offline = new WebPeerEvidence({ identity: this.appIdentity, sendControl: () => {}, onChange: () => this.render() });
    this.dialog = el('dialog'); this.dialog.className = 'evidence-dialog';
    this.title = el('h2'); this.title.dataset.i18n = 'evidence';
    this.help = el('p'); this.help.className = 'muted'; this.help.dataset.i18n = 'evidenceHelp';
    this.selector = el('select'); this.selector.id = 'evidence-peer'; this.selector.setAttribute('aria-label', t('verificationPartner')); this.selector.onchange = () => this.render();
    this.identity = el('pre'); this.identity.className = 'evidence-identity'; this.identity.id = 'evidence-identity';
    this.organization = el('p'); this.organization.id = 'organization-status'; this.organization.className = 'notice';
    this.status = el('p'); this.status.className = 'field-hint'; this.status.setAttribute('role', 'status');
    this.list = el('ol'); this.list.className = 'evidence-list'; this.list.id = 'evidence-list';
    this.actions = el('div'); this.actions.className = 'actions';
    this.button('evidenceExport', async () => { const epoch = this.epoch; const text = await this.current().exportBundle(); if (epoch === this.epoch) this.download(text, 'Intragram-audit.json'); });
    this.button('evidenceVerify', () => this.choose('verify'));
    this.button('evidenceWitness', () => this.choose('witness'));
    this.button('evidenceAttachAnchor', () => this.choose('anchor'));
    this.button('orgTrustImport', () => this.choose('trust'));
    this.button('orgCredentialImport', () => this.choose('credential'));
    this.button('close', () => this.dialog.close());
    this.file = el('input'); this.file.type = 'file'; this.file.accept = '.json,application/json'; this.file.hidden = true;
    this.file.onchange = () => this.action(async () => {
      const epoch = this.epoch, kind = this.fileKind;
      const guard = () => { if (epoch !== this.epoch) throw { code: 'evidence-invalid' }; };
      const file = this.file.files[0]; this.file.value = ''; if (!file) return;
      if (file.size > (kind === 'credential' ? 8192 : kind === 'trust' ? 256 * 1024 : 4 * 1024 * 1024)) throw { code: 'evidence-invalid' };
      const text = await file.text(); guard(); const evidence = this.current();
      if (kind === 'verify') { const valid = await evidence.importBundle(text); guard(); this.status.textContent = t(valid ? 'evidenceValid' : 'evidenceInvalid'); }
      else if (kind === 'witness') { const anchor = await evidence.witnessBundle(text); guard(); this.download(anchor, 'Intragram-witness-anchor.json'); this.status.textContent = t('evidenceWitnessed'); }
      else if (kind === 'anchor') { const valid = await evidence.attachAnchor(text, evidence.peerIdentity?.peerId); guard(); this.status.textContent = t(valid ? 'evidenceAnchorAttached' : 'evidenceInvalid'); }
      else if (kind === 'trust') { await this.setTrust(text); guard(); this.status.textContent = t('orgTrustLoaded'); }
      else { await this.setCredential(text); guard(); this.status.textContent = t('orgCredentialLoaded'); }
      this.render();
    });
    this.dialog.append(this.title, this.help, this.selector, this.identity, this.organization, this.actions, this.status, this.list, this.file); document.body.append(this.dialog);
    for (const id of ['evidence-open', 'global-evidence']) document.getElementById(id).onclick = () => {
      this.refresh(); this.populate(); this.render(); this.dialog.showModal();
    };
    document.addEventListener('visibilitychange', () => { if (document.hidden && this.dialog.open) this.dialog.close(); });
    this.prepareIdentity();
  }
  prepareIdentity() { const epoch = this.epoch; this.offline.ready().then(() => { if (epoch === this.epoch) this.render(); }).catch(error => { if (epoch === this.epoch) this.onError(error); }); }
  async setTrust(text) { await Promise.all([this.offline, ...[...this.peers.values()].map(item => item.evidence)].map(evidence => evidence.setTrustBundle(text))); }
  async setCredential(text) {
    await this.offline.setCredential(text);
    for (const item of this.peers.values()) { item.evidence.credential = this.offline.credential; await item.ready; await item.evidence.presentCredential(); }
  }
  current() { return this.peers.get(this.selector.value)?.evidence || this.peers.get(this.getSession()?.primary?.id)?.evidence || this.offline; }
  button(key, action) { const button = el('button'); button.type = 'button'; button.className = 'button'; button.dataset.i18n = key; button.dataset.evidenceAction = key; button.onclick = () => this.action(action); this.actions.append(button); }
  async action(action) {
    const epoch = this.epoch;
    for (const b of this.actions.querySelectorAll('button')) b.disabled = true;
    try { await action(); } catch (e) { if (epoch === this.epoch) this.status.textContent = t(e?.code === 'not-connected' ? 'not-connected' : 'evidenceInvalid'); }
    finally { if (epoch === this.epoch) for (const b of this.actions.querySelectorAll('button')) b.disabled = false; }
  }
  choose(kind) { this.fileKind = kind; this.file.click(); }
  attach(record) {
    if (!record?.peer.sessionBinding) return null;
    if (this.peers.has(record.id)) return this.peers.get(record.id);
    const epoch = this.epoch;
    const evidence = new WebPeerEvidence({ identity: this.appIdentity, sendControl: c => record.peer.sendControl(c), onChange: () => this.render(), alias: 'Web' });
    evidence.trust = this.offline.trust; evidence.credential = this.offline.credential;
    const item = { record, evidence, ready: null };
    this.peers.set(record.id, item);
    item.ready = evidence.start(record.peer.sessionBinding, { dialled: record.peer.pc?.localDescription?.type === 'offer' }).catch(e => { if (epoch === this.epoch) this.onError(e); });
    const pending = this.pending.get(record.id) || []; this.pending.delete(record.id);
    for (const c of pending) item.ready.then(() => epoch === this.epoch ? evidence.receive(c) : undefined).catch(e => { if (epoch === this.epoch) this.onError(e); });
    this.populate(); return item;
  }
  receive(record, control) {
    const epoch = this.epoch;
    const item = this.attach(record);
    if (!item) { const pending = this.pending.get(record.id) || []; if (pending.length < 32) pending.push(control); this.pending.set(record.id, pending); return; }
    item.ready.then(() => epoch === this.epoch ? item.evidence.receive(control) : undefined).catch(e => { if (epoch === this.epoch) this.onError(e); });
  }
  expectFile(record, id, file) {
    const item = this.attach(record), epoch = this.epoch;
    file.arrayBuffer().then(buffer => { if (epoch === this.epoch) return item.ready.then(() => item.evidence.expectFile(id, new Uint8Array(buffer))); }).catch(e => this.onError(e));
  }
  received(transfer) {
    if (transfer.direction !== 'receive' || transfer.state !== 'complete' || !transfer.blob) return;
    const item = this.peers.get(transfer.peerId), epoch = this.epoch; if (!item) return;
    transfer.blob.arrayBuffer().then(buffer => { if (epoch === this.epoch) return item.ready.then(() => item.evidence.recordFile(transfer.id, new Uint8Array(buffer))); }).catch(e => this.onError(e));
  }
  burn(message) {
    const session = this.getSession();
    const target = session?.isHost ? this.peers.get(message.origin) : this.peers.get(session?.primary?.id);
    if (target && !message.mine) target.ready.then(() => target.evidence.recordBurn(message.id, message.text)).catch(e => this.onError(e));
  }
  populate() {
    const previous = this.selector.value; this.selector.replaceChildren();
    for (const [id, item] of this.peers) { const option = el('option', item.record.alias || t('theirs')); option.value = id; this.selector.append(option); }
    if (this.peers.has(previous)) this.selector.value = previous;
    else if (this.peers.has(this.getSession()?.primary?.id)) this.selector.value = this.getSession().primary.id;
    this.selector.hidden = this.peers.size < 2;
  }
  render() {
    const evidence = this.current();
    this.identity.textContent = `${t('myIdentity')}: ${evidence.peerId || '—'}\n${t('myPublicKey')}: ${evidence.publicKey || '—'}\n${t('peerIdentity')}: ${evidence.peerIdentity?.peerId || '—'}`;
    const org = evidence.organization;
    this.organization.textContent = org ? `${t(org.verified ? 'orgVerified' : 'orgUnverified')} · ${org.credential.org} · ${org.credential.dept} · ${org.credential.role} · ${org.check}${org.demo ? ` · ${t('orgDemo')}` : ''}` : t('orgNotPresented');
    this.list.replaceChildren();
    for (const entry of evidence.entries.slice().reverse()) {
      const a = entry.attestation, item = el('li'); item.append(el('strong', t(`proof-${entry.status}`)), el('p', `${a.k} · ${a.p} · ${a.s}`), el('small', new Date(a.t).toLocaleString())); this.list.append(item);
    }
  }
  download(text, name) {
    const url = URL.createObjectURL(new Blob([text], { type: 'application/json' })); const link = el('a'); link.href = url; link.download = name; document.body.append(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 10000);
  }
  refresh() { for (const element of this.dialog.querySelectorAll('[data-i18n]')) element.textContent = t(element.dataset.i18n); this.render(); }
  clear({ rotateIdentity = false } = {}) {
    this.epoch++;
    for (const item of this.peers.values()) item.evidence.clear(); this.peers.clear(); this.pending.clear();
    const credential = this.offline.credential, trust = this.offline.trust;
    this.offline.clear();
    if (rotateIdentity) {
      this.appIdentity.clear(); this.appIdentity = new WebPeerIdentity();
      this.offline = new WebPeerEvidence({ identity: this.appIdentity, sendControl: () => {}, onChange: () => this.render() });
    } else { this.offline.credential = credential; this.offline.trust = trust; }
    this.selector.replaceChildren(); this.list.replaceChildren(); this.identity.textContent = ''; this.organization.textContent = ''; this.status.textContent = '';
    for (const button of this.actions.querySelectorAll('button')) button.disabled = false;
    if (this.dialog.open) this.dialog.close();
    this.prepareIdentity();
  }
}
