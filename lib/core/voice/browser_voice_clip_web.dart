import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'voice_clip.dart';
import 'voice_wav.dart';

class BrowserVoiceClip extends PolledVoiceClip {
  BrowserVoiceClip._(this._audio, this._url, super.duration);
  final web.HTMLAudioElement _audio;
  final String _url;

  static Future<VoiceClip> load(PcmWav wav) async {
    final pcm = wav.pcm;
    final bytes = Uint8List(44 + pcm.length)
      ..setRange(44, 44 + pcm.length, pcm);
    final h = ByteData.sublistView(bytes)
      ..setUint32(4, 36 + pcm.length, Endian.little)
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, wav.channels, Endian.little)
      ..setUint32(24, wav.sampleRate, Endian.little)
      ..setUint32(28, wav.byteRate, Endian.little)
      ..setUint16(32, wav.channels * 2, Endian.little)
      ..setUint16(34, 16, Endian.little)
      ..setUint32(40, pcm.length, Endian.little);
    const tags = {0: 'RIFF', 8: 'WAVE', 12: 'fmt ', 36: 'data'};
    tags.forEach((at, tag) {
      for (var i = 0; i < 4; i++) {
        h.setUint8(at + i, tag.codeUnitAt(i));
      }
    });
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'audio/wav'),
    );
    final url = web.URL.createObjectURL(blob);
    return BrowserVoiceClip._(
      web.HTMLAudioElement()..src = url,
      url,
      wav.duration,
    );
  }

  @override
  Future<void> startOutput({required bool rewind}) async {
    if (rewind) _audio.currentTime = 0;
    await _audio.play().toDart;
  }

  @override
  Future<void> pauseOutput() async => _audio.pause();
  @override
  Future<Duration> outputPosition() async =>
      Duration(milliseconds: (_audio.currentTime * 1000).round());
  @override
  Future<bool> outputFinished() async => _audio.ended;
  @override
  Future<void> releaseOutput() async {
    _audio.pause();
    _audio.removeAttribute('src');
    _audio.load();
    web.URL.revokeObjectURL(_url);
  }
}
