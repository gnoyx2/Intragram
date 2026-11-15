import 'dart:io';
import 'dart:typed_data';
import 'registry/incoming_path_resolver.dart';

Future<String?> storeWebReceived(
  String name,
  Uint8List bytes, {
  Future<String?> Function(String)? chooseDirectory,
  required bool Function() wanted,
}) async {
  final dir =
      await (chooseDirectory == null
              ? webReceivePaths
              : IncomingPathResolver(chooseDirectory: chooseDirectory))
          .saveDir(name);
  if (dir == null || !wanted()) return null;
  return IncomingPathResolver.saveBytes(
    directory: dir,
    name: name,
    bytes: bytes,
    isStillWanted: wanted,
  );
}

Stream<List<int>> openWebSource(String path) => File(path).openRead();
void discardWebReceived(String path) {}
void clearWebReceived() => webReceivePaths.clear();
