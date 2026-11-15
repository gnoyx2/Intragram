import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

import '../core/browser_received_files_web.dart';
import 'web_stream_types.dart';

extension type _HandleCap(JSObject _) implements JSObject {
  external JSFunction? get createWritable;
}

Future<WebByteSource> webSourceFromPath(String path) async =>
    StreamWebByteSource(
      await BrowserReceivedFiles.lengthOf(path),
      () =>
          BrowserReceivedFiles.openRead(path, chunkSize: kWebStreamChunkBytes),
    );

Future<WebByteSource> webSourceFromPlatformFile(PlatformFile file) async {
  final uriStr = file.uri.toString();
  if (BrowserReceivedFiles.contains(uriStr)) return webSourceFromPath(uriStr);
  final len = file.lengthSync() ?? await file.length();
  if (uriStr.startsWith('blob:')) {
    return StreamWebByteSource(len, () => _fetchBlobChunks(uriStr));
  }
  if (uriStr.startsWith('data:')) {
    return MemoryWebByteSource(
      Uri.parse(uriStr).data?.contentAsBytes() ?? Uint8List(0),
    );
  }
  if (len == 0 && uriStr.isEmpty) return MemoryWebByteSource(Uint8List(0));
  return StreamWebByteSource(len, file.readAsByteStream);
}

Future<WebReceiveSink?> openWebReceiveSink(
  String name,
  int totalBytes, {
  Future<String?> Function(String)? chooseDirectory,
  required bool Function() wanted,
}) async {
  if (!wanted()) return null;
  await BrowserReceivedFiles.checkStorageQuota(
    totalBytes + kWebReceiveHeadroomBytes,
  );
  if (!wanted()) return null;
  final opfs = await _tryOpenOpfsSink(name, totalBytes, wanted);
  if (opfs != null) return opfs;
  if (!wanted()) return null;
  if (totalBytes > kWebFallbackReceiveMaxBytes) {
    throw StateError('insufficient-storage');
  }
  return MemoryBufferReceiveSink(
    (bytes) => BrowserReceivedFiles.put(name, bytes),
  );
}

Future<void> sweepWebStreamTemp() =>
    BrowserReceivedFiles.sweepBrowserTempFiles();

// 커밋이 끝난 뒤 취소된 전송의 파일: 탭 메모리·OPFS 항목을 지움 (onRemove가 OPFS 파일도 지움)
Future<void> discardCommittedWebFile(String path) async =>
    BrowserReceivedFiles.remove(path);

Future<WebReceiveSink?> _tryOpenOpfsSink(
  String name,
  int totalBytes,
  bool Function() wanted,
) async {
  web.FileSystemDirectoryHandle? dir;
  String? tempName;
  try {
    dir = await BrowserReceivedFiles.sessionDir();
    if (dir == null) return null;
    final rng = Random.secure();
    final hex = List<String>.generate(
      8,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    tempName = 'recv-${DateTime.now().millisecondsSinceEpoch}-$hex.part';
    final handle = await dir
        .getFileHandle(tempName, web.FileSystemGetFileOptions(create: true))
        .toDart;
    if (_HandleCap(handle).createWritable == null) {
      await _removeQuietly(dir, tempName);
      return null;
    }
    final writable = await handle.createWritable().toDart;
    if (!wanted()) {
      await _ignore(writable.abort().toDart);
      await _removeQuietly(dir, tempName);
      return null;
    }
    return _OpfsReceiveSink(name, totalBytes, dir, tempName, handle, writable);
  } on Object {
    if (dir != null && tempName != null) await _removeQuietly(dir, tempName);
    return null;
  }
}

Future<void> _ignore(Future<Object?> future) async {
  try {
    await future;
  } on Object {
    return;
  }
}

Future<void> _removeQuietly(web.FileSystemDirectoryHandle d, String n) =>
    _ignore(d.removeEntry(n).toDart);

Stream<Uint8List> _fetchBlobChunks(String url) async* {
  final response = await web.window.fetch(url.toJS).toDart;
  if (!response.ok && response.status != 0) {
    throw StateError('file no longer available');
  }
  final body = response.body;
  if (body == null) {
    yield (await response.arrayBuffer().toDart).toDart.asUint8List();
    return;
  }
  final reader = web.ReadableStreamDefaultReader(body);
  try {
    while (true) {
      final res = await reader.read().toDart;
      if (res.done) break;
      final val = res.value;
      if (!val.isUndefinedOrNull) yield (val! as JSUint8Array).toDart;
    }
  } finally {
    await _ignore(reader.cancel().toDart);
  }
}

final class _OpfsReceiveSink implements WebReceiveSink {
  _OpfsReceiveSink(
    this._name,
    int totalBytes,
    this._dir,
    this._tempName,
    this._handle,
    this._writable,
  ) : _preview = totalBytes <= kWebInlinePreviewCacheMaxBytes
          ? BytesBuilder()
          : null;

  final String _name;
  final web.FileSystemDirectoryHandle _dir;
  final String _tempName;
  final web.FileSystemFileHandle _handle;
  final web.FileSystemWritableFileStream _writable;
  BytesBuilder? _preview;
  bool _closed = false, _committed = false, _aborted = false;

  @override
  Future<void> write(Uint8List chunk) async {
    if (_closed) throw StateError('sink closed');
    if (chunk.isEmpty) return;
    final preview = _preview;
    if (preview != null) {
      if (preview.length + chunk.length <= kWebInlinePreviewCacheMaxBytes) {
        preview.add(chunk);
      } else {
        zeroBytesBuilder(preview);
        _preview = null;
      }
    }
    await _writable.write(chunk.toJS).toDart;
  }

  @override
  Future<String?> commit({required bool Function() wanted}) async {
    if (_closed) throw StateError('sink already finalized');
    _closed = true;
    try {
      await _writable.close().toDart;
      if (!wanted()) {
        _aborted = true;
        zeroBytesBuilder(_preview);
        _preview = null;
        await _removeQuietly(_dir, _tempName);
        return null;
      }
      final jsFile = await _handle.getFile().toDart;
      final previewBytes = _preview?.takeBytes();
      _preview = null;
      final url = BrowserReceivedFiles.putBlob(
        _name,
        jsFile,
        inlinePreviewBytes: previewBytes,
        onRemove: () => unawaited(_removeQuietly(_dir, _tempName)),
      );
      previewBytes?.fillRange(0, previewBytes.length, 0);
      _committed = true;
      return url;
    } on Object {
      zeroBytesBuilder(_preview);
      _preview = null;
      await _removeQuietly(_dir, _tempName);
      rethrow;
    }
  }

  @override
  Future<void> abort() async {
    if (_committed || _aborted) return;
    _aborted = true;
    _closed = true;
    zeroBytesBuilder(_preview);
    _preview = null;
    await _ignore(_writable.abort().toDart);
    await _removeQuietly(_dir, _tempName);
  }
}
