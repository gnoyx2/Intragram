import 'voice_clip.dart';
import 'voice_wav.dart';

abstract final class WaveOutVoiceClip {
  static Future<VoiceClip> load(PcmWav wav) =>
      Future.error(UnsupportedError('Windows audio output is unavailable'));
}
