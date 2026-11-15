import 'voice_clip.dart';
import 'voice_wav.dart';

abstract final class BrowserVoiceClip {
  static Future<VoiceClip> load(PcmWav wav) =>
      Future.error(UnsupportedError('Browser audio is unavailable'));
}
