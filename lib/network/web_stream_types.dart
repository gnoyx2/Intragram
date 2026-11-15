import 'dart:typed_data';

import 'package:meta/meta.dart' show visibleForTesting;

const int kWebStreamChunkBytes = 64 * 1024;
const int kWebInlinePreviewCacheMaxBytes = 25 * 1024 * 1024;
const int kWebReceiveHeadroomBytes = 16 * 1024 * 1024;
const int kWebFallbackReceiveMaxBytes = 100 * 1024 * 1024;

abstract interface class WebByteSource {
  int get length;
  Stream<Uint8List> openRead();
  Future<void> dispose();
}

final class MemoryWebByteSource implements WebByteSource {
  MemoryWebByteSource(Uint8List bytes)
    : _bytes = Uint8List.fromList(bytes),
      length = bytes.length;

  final Uint8List _bytes;
  bool _disposed = false;

  @override
  final int length;

  @visibleForTesting
  Uint8List get debugBuffer => _bytes;

  @override
  Stream<Uint8List> openRead() {
    if (_disposed) throw StateError('source disposed');
    return _readChunks();
  }

  Stream<Uint8List> _readChunks() async* {
    for (
      var offset = 0;
      offset < _bytes.length;
      offset += kWebStreamChunkBytes
    ) {
      if (_disposed) throw StateError('source disposed');
      final end = offset + kWebStreamChunkBytes < _bytes.length
          ? offset + kWebStreamChunkBytes
          : _bytes.length;
      yield Uint8List.fromList(Uint8List.sublistView(_bytes, offset, end));
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _bytes.fillRange(0, _bytes.length, 0);
  }
}

final class StreamWebByteSource implements WebByteSource {
  StreamWebByteSource(this.length, this._open);

  final Stream<List<int>> Function() _open;
  bool _disposed = false;

  @override
  final int length;

  @override
  Stream<Uint8List> openRead() {
    if (_disposed) throw StateError('source disposed');
    return rechunkByteStream(_open());
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}

abstract interface class WebReceiveSink {
  Future<void> write(Uint8List chunk);
  Future<String?> commit({required bool Function() wanted});
  Future<void> abort();
}

final class MemoryBufferReceiveSink implements WebReceiveSink {
  MemoryBufferReceiveSink(
    this._onCommit, {
    this.maxBytes = kWebFallbackReceiveMaxBytes,
  });

  final String Function(Uint8List bytes) _onCommit;
  final int maxBytes;
  final BytesBuilder _builder = BytesBuilder();
  bool _closed = false;
  bool _committed = false;
  bool _aborted = false;

  @override
  Future<void> write(Uint8List chunk) async {
    if (_closed) throw StateError('sink closed');
    if (chunk.isEmpty) return;
    if (_builder.length + chunk.length > maxBytes) {
      zeroBytesBuilder(_builder);
      throw StateError('insufficient-storage');
    }
    _builder.add(chunk);
  }

  @override
  Future<String?> commit({required bool Function() wanted}) async {
    if (_closed) throw StateError('sink already finalized');
    _closed = true;
    final bytes = _builder.takeBytes();
    if (!wanted()) {
      _aborted = true;
      bytes.fillRange(0, bytes.length, 0);
      return null;
    }
    final path = _onCommit(bytes);
    bytes.fillRange(0, bytes.length, 0);
    _committed = true;
    return path;
  }

  @override
  Future<void> abort() async {
    if (_committed || _aborted) return;
    _aborted = true;
    _closed = true;
    zeroBytesBuilder(_builder);
  }
}

void zeroBytesBuilder(BytesBuilder? builder) {
  if (builder == null) return;
  final buf = builder.takeBytes();
  buf.fillRange(0, buf.length, 0);
}

Stream<Uint8List> rechunkByteStream(
  Stream<List<int>> source, {
  int maxChunkBytes = kWebStreamChunkBytes,
}) async* {
  await for (final raw in source) {
    if (raw.isEmpty) continue;
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
    if (bytes.length <= maxChunkBytes) {
      yield bytes;
      continue;
    }
    for (var offset = 0; offset < bytes.length; offset += maxChunkBytes) {
      final end = offset + maxChunkBytes < bytes.length
          ? offset + maxChunkBytes
          : bytes.length;
      yield Uint8List.sublistView(bytes, offset, end);
    }
  }
}
