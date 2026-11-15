import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../core/free_space.dart';
import 'registry/incoming_path_resolver.dart';
import 'web_stream_types.dart';

Future<WebByteSource> webSourceFromPath(String path) async {
  final file = File(path);
  final len = await file.length();
  return StreamWebByteSource(len, file.openRead);
}

Future<WebByteSource> webSourceFromPlatformFile(PlatformFile file) async {
  final path = file.path;
  if (path != null) return webSourceFromPath(path);
  final len = file.lengthSync() ?? await file.length();
  return StreamWebByteSource(len, file.readAsByteStream);
}

Future<WebReceiveSink?> openWebReceiveSink(
  String name,
  int totalBytes, {
  Future<String?> Function(String)? chooseDirectory,
  required bool Function() wanted,
}) async {
  final paths = chooseDirectory == null
      ? webReceivePaths
      : IncomingPathResolver(chooseDirectory: chooseDirectory);
  final dir = await paths.saveDir(name);
  if (dir == null || !wanted()) return null;
  final free = freeBytesAt(dir) ?? freeBytesAt(Directory(dir).parent.path);
  if (free != null && totalBytes + kWebReceiveHeadroomBytes > free) {
    // 공간 부족이면 고른 폴더를 잊어서 다시 받을 때 다른 폴더를 물음 (v7과 같음)
    paths.clear();
    throw StateError('insufficient-storage');
  }
  final reserved = await IncomingPathResolver.reserveDestination(
    directory: dir,
    name: name,
    attemptId: 'web-${DateTime.now().microsecondsSinceEpoch}',
  );
  if (!wanted()) {
    await _deleteIfExists(reserved.partial);
    return null;
  }
  final RandomAccessFile raf;
  try {
    raf = await reserved.partial.open(mode: FileMode.writeOnly);
  } on Object {
    await _deleteIfExists(reserved.partial);
    rethrow;
  }
  if (!wanted()) {
    await _closeQuietly(raf);
    await _deleteIfExists(reserved.partial);
    return null;
  }
  return _NativeWebReceiveSink(reserved.partial, reserved.finalName, raf);
}

Future<void> sweepWebStreamTemp() async {}

// 커밋이 끝난 뒤 취소된 전송의 파일: 이 수신이 방금 만든 최종 파일만 지움
Future<void> discardCommittedWebFile(String path) =>
    _deleteIfExists(File(path));

final class _NativeWebReceiveSink implements WebReceiveSink {
  _NativeWebReceiveSink(this._partial, this._finalName, this._raf);

  final File _partial;
  final String _finalName;
  final RandomAccessFile _raf;
  bool _closed = false;
  bool _committed = false;
  bool _aborted = false;
  // 진행 중인 쓰기: 그 사이 close하면 실패하고 fd가 열린 채 남음 (.part도 Windows에선 못 지움)
  Future<void> _tail = Future<void>.value();

  @override
  Future<void> write(Uint8List chunk) async {
    if (_closed) throw StateError('sink closed');
    if (chunk.isEmpty) return;
    final writing = _raf.writeFrom(chunk);
    _tail = writing.then<void>((_) {}, onError: (Object _) {});
    await writing;
  }

  @override
  Future<String?> commit({required bool Function() wanted}) async {
    if (_closed) throw StateError('sink already finalized');
    _closed = true;
    await _tail;
    try {
      await _raf.flush();
      await _raf.close();
    } on Object {
      await _closeQuietly(_raf);
      await _deleteIfExists(_partial);
      rethrow;
    }
    if (!wanted()) {
      _aborted = true;
      await _deleteIfExists(_partial);
      return null;
    }
    try {
      final committedPath = await IncomingPathResolver.commitDestination(
        _partial,
        _finalName,
      );
      _committed = true;
      return committedPath;
    } on Object {
      await _deleteIfExists(_partial);
      rethrow;
    }
  }

  @override
  Future<void> abort() async {
    if (_committed || _aborted) return;
    _aborted = true;
    _closed = true;
    await _tail;
    await _closeQuietly(_raf);
    await _deleteIfExists(_partial);
  }
}

Future<void> _closeQuietly(RandomAccessFile raf) async {
  try {
    await raf.close();
  } on Object {
    return;
  }
}

Future<void> _deleteIfExists(File file) async {
  try {
    if (file.existsSync()) await file.delete();
  } on Object {
    return;
  }
}
