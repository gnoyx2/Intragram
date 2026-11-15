import 'dart:async';
import 'dart:typed_data';

import '../core/browser_received_files.dart';
import 'web_stream_io.dart';

Future<String?> storeWebReceived(
  String name,
  Uint8List bytes, {
  Future<String?> Function(String)? chooseDirectory,
  required bool Function() wanted,
}) async => wanted() ? BrowserReceivedFiles.put(name, bytes) : null;

Stream<List<int>> openWebSource(String path) =>
    BrowserReceivedFiles.openRead(path);

void discardWebReceived(String path) => BrowserReceivedFiles.remove(path);

void clearWebReceived() {
  BrowserReceivedFiles.clear();
  unawaited(sweepWebStreamTemp());
}
