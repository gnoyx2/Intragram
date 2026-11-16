import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

part 'browser_received_files_session.dart';

typedef _BrowserFileEntry = ({
  String name,
  Uint8List? bytes,
  web.Blob blob,
  void Function()? onRemove,
});

extension type _SafeNavigator(JSObject _) implements JSObject {
  external _SafeStorageManager? get storage;
  external web.LockManager? get locks;
}

extension type _SafeStorageManager(JSObject _) implements JSObject {
  external JSFunction? get estimate;
  external JSFunction? get getDirectory;
  @JS('estimate')
  external JSPromise<_SafeEstimate> callEstimate();
  @JS('getDirectory')
  external JSPromise<web.FileSystemDirectoryHandle> callGetDirectory();
}

extension type _SafeEstimate(JSObject _) implements JSObject {
  external JSNumber? get usage;
  external JSNumber? get quota;
}

// Session-only browser store. Explicit download is the sole user persistence path.
abstract final class BrowserReceivedFiles {
  static const String tempDirName = 'intragram-recv-tmp';

  static final _files = <String, _BrowserFileEntry>{};
  // 일회성 다운로드 사본을 지우는 타이머 (clear가 사본을 먼저 지우면 같이 멈춤)
  static final _expiring = <Timer>{};

  static String put(String name, Uint8List bytes) {
    final copy = Uint8List.fromList(bytes);
    final blob = web.Blob(
      [copy.toJS].toJS,
      web.BlobPropertyBag(type: 'application/octet-stream'),
    );
    final url = web.URL.createObjectURL(blob);
    _files[url] = (name: name, bytes: copy, blob: blob, onRemove: null);
    return url;
  }

  static String putBlob(
    String name,
    Object blob, {
    Uint8List? inlinePreviewBytes,
    void Function()? onRemove,
  }) {
    final jsBlob = blob as web.Blob;
    final preview = inlinePreviewBytes == null
        ? null
        : Uint8List.fromList(inlinePreviewBytes);
    final url = web.URL.createObjectURL(jsBlob);
    _files[url] = (
      name: name,
      bytes: preview,
      blob: jsBlob,
      onRemove: onRemove,
    );
    return url;
  }

  static Uint8List? read(String path) {
    final bytes = _files[path]?.bytes;
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  static String? nameOf(String path) => _files[path]?.name;

  static web.Blob? blobOf(String path) => _files[path]?.blob;

  static Stream<Uint8List> openRead(String path, {int chunkSize = 64 * 1024}) {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be positive');
    }
    if (!contains(path)) throw StateError('file no longer available');
    return _readChunks(path, chunkSize);
  }

  static Stream<Uint8List> _readChunks(String path, int chunkSize) async* {
    final entry = _files[path];
    if (entry == null) throw StateError('file no longer available');
    final bytes = entry.bytes;
    if (bytes != null) {
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        if (!_files.containsKey(path)) {
          throw StateError('file no longer available');
        }
        final end = offset + chunkSize < bytes.length
            ? offset + chunkSize
            : bytes.length;
        yield Uint8List.fromList(Uint8List.sublistView(bytes, offset, end));
      }
      return;
    }
    final blob = entry.blob;
    final total = blob.size;
    for (var offset = 0; offset < total; offset += chunkSize) {
      if (!_files.containsKey(path)) {
        throw StateError('file no longer available');
      }
      final end = offset + chunkSize < total ? offset + chunkSize : total;
      final buffer = await blob.slice(offset, end).arrayBuffer().toDart;
      yield buffer.toDart.asUint8List();
    }
  }

  static Future<int> lengthOf(String path) async {
    final entry = _files[path];
    if (entry == null) throw StateError('file no longer available');
    return entry.bytes?.length ?? entry.blob.size;
  }

  static bool contains(String path) => _files.containsKey(path);

  // 받은 파일 목록에 안 남는 일회성 다운로드 (음성 저장). 탭 메모리 사본은 다운로드가 시작된 뒤 지움
  static void download(String name, Uint8List bytes) {
    final copy = put(name, bytes);
    save(copy);
    late final Timer timer;
    timer = Timer(const Duration(minutes: 1), () {
      _expiring.remove(timer);
      remove(copy);
    });
    _expiring.add(timer);
  }

  static bool save(String path, [String? name]) {
    final file = _files[path];
    if (file == null) return false;
    final anchor = web.HTMLAnchorElement()
      ..href = path
      ..download = name ?? file.name
      ..style.display = 'none';
    // 문서에 붙은 링크만 클릭으로 받는 브라우저가 있어서 잠깐 붙였다 뗌
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    return true;
  }

  static void remove(String path) {
    final file = _files.remove(path);
    final bytes = file?.bytes;
    bytes?.fillRange(0, bytes.length, 0);
    web.URL.revokeObjectURL(path);
    try {
      file?.onRemove?.call();
    } on Object {
      // Ignore cleanup callback errors.
    }
  }

  static void clear() {
    for (final timer in _expiring) {
      timer.cancel();
    }
    _expiring.clear();
    for (final path in _files.keys.toList()) {
      remove(path);
    }
    unawaited(sweepBrowserTempFiles());
  }

  static Future<void> checkStorageQuota(int requiredBytes) async {
    final storage = _SafeNavigator(web.window.navigator).storage;
    if (storage == null || storage.estimate == null) return;
    final _SafeEstimate est;
    try {
      est = await storage.callEstimate().toDart;
    } on Object {
      return;
    }
    final quota = est.quota?.toDartDouble.floor();
    final usage = est.usage?.toDartDouble.floor();
    if (quota != null &&
        usage != null &&
        quota > 0 &&
        usage >= 0 &&
        (quota - usage) < requiredBytes) {
      throw StateError('insufficient-storage');
    }
  }

  static Future<web.FileSystemDirectoryHandle?> sessionDir() => _sessionDir();

  static Future<void> sweepStaleTemp() => _sweepStaleTemp();

  static Future<void> sweepBrowserTempFiles() async {
    try {
      final storage = _SafeNavigator(web.window.navigator).storage;
      if (storage == null || storage.getDirectory == null) return;
      final root = await storage.callGetDirectory().toDart;
      await root
          .removeEntry(
            tempDirName,
            web.FileSystemRemoveOptions(recursive: true),
          )
          .toDart;
    } on Object {
      // Ignore NotFoundError or unavailable OPFS.
    }
  }
}
