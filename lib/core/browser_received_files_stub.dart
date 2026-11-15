import 'dart:typed_data';

abstract final class BrowserReceivedFiles {
  static const String tempDirName = 'intragram-recv-tmp';

  static String put(String name, Uint8List bytes) =>
      throw UnsupportedError('Browser file store is unavailable');

  static String putBlob(
    String name,
    Object blob, {
    Uint8List? inlinePreviewBytes,
    void Function()? onRemove,
  }) => throw UnsupportedError('Browser file store is unavailable');

  static Uint8List? read(String path) => null;

  static String? nameOf(String path) => null;

  static Stream<Uint8List> openRead(String path, {int chunkSize = 64 * 1024}) =>
      throw UnsupportedError('Browser file store is unavailable');

  static Future<int> lengthOf(String path) async =>
      throw StateError('file no longer available');

  static bool contains(String path) => false;
  static bool save(String path, [String? name]) => false;
  static void download(String name, Uint8List bytes) =>
      throw UnsupportedError('Browser file store is unavailable');
  static void remove(String path) {}
  static void clear() {}
  static Future<void> checkStorageQuota(int requiredBytes) async {}
  static Future<void> sweepBrowserTempFiles() async {}
  static Future<void> sweepStaleTemp() async {}
}
