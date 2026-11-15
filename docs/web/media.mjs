import { t } from './i18n.mjs';

const $ = id => document.getElementById(id);
const node = (tag, text) => { const el = document.createElement(tag); if (text) el.textContent = text; return el; };
export function pcmWav(samples, sampleRate = 16000) {
  const bytes = new ArrayBuffer(44 + samples.length * 2), view = new DataView(bytes);
  const word = (offset, text) => { for (let i = 0; i < text.length; i++) view.setUint8(offset + i, text.charCodeAt(i)); };
  word(0, 'RIFF'); view.setUint32(4, bytes.byteLength - 8, true); word(8, 'WAVE'); word(12, 'fmt ');
  view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true); view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true); word(36, 'data'); view.setUint32(40, samples.length * 2, true);
  for (let i = 0; i < samples.length; i++) { const sample = Math.max(-1, Math.min(1, samples[i])); view.setInt16(44 + i * 2, sample < 0 ? sample * 32768 : sample * 32767, true); }
  return bytes;
}
async function recordedWav(blob) {
  const audioContext = new AudioContext();
  try {
    const decoded = await audioContext.decodeAudioData(await blob.arrayBuffer());
    const offline = new OfflineAudioContext(1, Math.max(1, Math.ceil(Math.min(decoded.duration, 60) * 16000)), 16000);
    const source = offline.createBufferSource(); source.buffer = decoded; source.connect(offline.destination); source.start();
    const rendered = await offline.startRendering();
    return new Blob([pcmWav(rendered.getChannelData(0))], { type: 'audio/wav' });
  } finally { await audioContext.close(); }
}
export class MediaExperience {
  constructor({ getSession, onError, offerFile = file => getSession().offerFile(file) }) {
    this.getSession = getSession; this.onError = onError; this.epoch = 0;
    this.offerFile = offerFile;
    this.dialog = node('dialog'); this.dialog.className = 'voice-dialog';
    this.title = node('h2'); this.duration = node('p'); this.audio = node('audio'); this.audio.controls = true;
    const actions = node('div'); actions.className = 'actions';
    this.stopButton = node('button'); this.sendButton = node('button'); this.cancelButton = node('button');
    for (const button of [this.stopButton, this.sendButton, this.cancelButton]) { button.type = 'button'; button.className = 'button'; actions.append(button); }
    this.sendButton.classList.add('primary'); this.dialog.append(this.title, this.duration, this.audio, actions); document.body.append(this.dialog);
    this.stopButton.onclick = () => this.stop(false);
    this.cancelButton.onclick = () => { this.stop(true); this.dialog.close(); };
    this.sendButton.onclick = () => {
      try { this.offerFile(this.file); this.stop(true); this.dialog.close(); } catch (e) { this.onError(e); }
    };
    this.dialog.addEventListener('cancel', () => this.stop(true));
    this.dialog.addEventListener('close', () => { if (this.recorder?.state === 'recording') this.stop(true); });
    $('voice').onclick = () => this.start().catch(e => this.onError(e));
    document.addEventListener('visibilitychange', () => { if (document.hidden && this.recorder?.state === 'recording') this.stop(false); });
    window.addEventListener('pagehide', () => this.stop(true));
  }
  async start() {
    if (this.getSession()?.state !== 'connected') throw { code: 'not-connected' };
    if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) throw { code: 'microphone-unavailable' };
    this.stop(true); const epoch = this.epoch;
    this.title.textContent = t('recordVoice'); this.stopButton.textContent = t('stopRecording'); this.sendButton.textContent = t('send'); this.cancelButton.textContent = t('cancel');
    this.duration.textContent = t('microphoneRequest'); this.stopButton.disabled = true; this.sendButton.disabled = true; this.audio.hidden = true;
    this.dialog.showModal();
    let stream;
    try { stream = await navigator.mediaDevices.getUserMedia({ audio: true }); }
    catch { if (epoch !== this.epoch) return; this.dialog.close(); throw { code: 'microphone-denied' }; }
    if (epoch !== this.epoch || !this.dialog.open) { stream.getTracks().forEach(track => track.stop()); return; }
    this.stream = stream; this.parts = []; this.total = 0; this.startedAt = Date.now();
    const mimeType = ['audio/webm;codecs=opus', 'audio/mp4', 'audio/webm'].find(type => MediaRecorder.isTypeSupported(type));
    this.recorder = new MediaRecorder(stream, mimeType ? { mimeType } : {});
    this.recorder.ondataavailable = e => {
      if (epoch !== this.epoch || !e.data.size) return;
      this.total += e.data.size;
      if (this.total > 20 * 1024 * 1024) { this.stop(true); this.dialog.close(); this.onError({ code: 'invalid-file' }); return; }
      this.parts.push(e.data);
    };
    this.recorder.onstop = async () => {
      if (epoch !== this.epoch) return;
      const type = this.recorder.mimeType || 'audio/webm';
      const blob = new Blob(this.parts, { type }); this.parts = [];
      if (!blob.size) { this.sendButton.disabled = true; return; }
      let wav;
      try { wav = await recordedWav(blob); } catch { if (epoch === this.epoch) this.onError({ code: 'microphone-unavailable' }); return; }
      if (epoch !== this.epoch) return;
      this.file = new File([wav], `voice-${new Date().toISOString().replaceAll(':', '-')}.wav`, { type: 'audio/wav' });
      this.previewUrl = URL.createObjectURL(wav); this.audio.src = this.previewUrl; this.audio.hidden = false;
      this.sendButton.disabled = false; this.stopButton.disabled = true; this.duration.textContent = t('voiceReady');
    };
    this.recorder.onerror = () => { this.stop(true); this.dialog.close(); this.onError({ code: 'microphone-unavailable' }); };
    this.recorder.start(250); this.stopButton.disabled = false;
    this.tick = setInterval(() => {
      const seconds = Math.floor((Date.now() - this.startedAt) / 1000); this.duration.textContent = `${seconds}s / 60s`;
      if (seconds >= 60) this.stop(false);
    }, 250);
  }
  stop(discard) {
    if (discard) this.epoch++;
    clearInterval(this.tick);
    if (this.recorder?.state === 'recording') this.recorder.stop();
    this.stream?.getTracks().forEach(track => track.stop()); this.stream = null;
    if (discard) {
      this.audio.pause(); this.audio.removeAttribute('src'); this.audio.load();
      if (this.previewUrl) URL.revokeObjectURL(this.previewUrl);
      this.previewUrl = null; this.file = null; this.parts = []; this.recorder = null;
      if (this.dialog.open) this.dialog.close();
    }
  }
  preview(container, transfer, url) {
    const name = transfer.name.toLowerCase();
    if (/\.(png|jpe?g|gif|webp|avif)$/.test(name)) {
      const image = node('img'); image.src = url; image.alt = transfer.name; image.className = 'media-thumbnail'; image.loading = 'lazy';
      const open = node('button'); open.type = 'button'; open.className = 'image-open'; open.setAttribute('aria-label', `${t('previewImage')} ${transfer.name}`); open.append(image);
      open.onclick = () => {
        const dialog = node('dialog'); dialog.className = 'image-viewer'; const full = image.cloneNode(); full.loading = 'eager'; const close = node('button', t('close')); close.className = 'button'; close.type = 'button'; close.onclick = () => dialog.close();
        dialog.append(full, close); dialog.addEventListener('close', () => dialog.remove()); document.body.append(dialog); dialog.showModal();
      };
      container.append(open);
    } else if (/\.(wav|mp3|m4a|ogg|opus)$/.test(name) || /^voice-.*\.webm$/.test(name)) {
      const audio = node('audio'); audio.src = url; audio.controls = true; audio.preload = 'metadata'; audio.setAttribute('aria-label', transfer.name); container.append(audio);
    } else if (/\.(mp4|webm|mov)$/.test(name)) {
      const video = node('video'); video.src = url; video.controls = true; video.preload = 'metadata'; video.playsInline = true; video.setAttribute('aria-label', transfer.name); container.append(video);
    }
  }
}
