import 'dart:typed_data';

abstract final class BrowserClipboard {
  static bool get canRead => false;
  static Future<Uint8List?> readImage() async => null;
  static Future<List<String>> readFiles() async => [];
}
