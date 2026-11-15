import 'dart:typed_data';

// Windows-specific clipboard flags are unavailable to a browser.
abstract final class WindowsClipboard {
  static bool setPrivateText(String text) => false;
  static void clearIfOwn() {}
  static ({bool image, bool files})? kinds() => null;
  static Uint8List? readImage() => null;
}
