import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/browser_received_files.dart';
import 'package:intragram/network/registry/incoming_session_files.dart';
import 'package:intragram/network/web_stream_io.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart' show XFile;

final class _TestPlatformFile extends PlatformFile {
  _TestPlatformFile(this.name, this.uri, this._size, this._openStream);
  @override
  final String name;
  @override
  final Uri uri;
  final int _size;
  final Stream<Uint8List> Function() _openStream;
  @override
  XFile get xFile => XFile(uri.toString(), name: name);
  @override
  int? lengthSync() => _size;
  @override
  Future<int> length() async => _size;
  @override
  Future<Uint8List> readAsBytes() async => _collect(_openStream());
  @override
  Stream<Uint8List> readAsByteStream() => _openStream();
}

Future<Uint8List> _collect(Stream<Uint8List> stream) async {
  final out = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    expect(chunk.length, inInclusiveRange(1, kWebStreamChunkBytes));
    out.add(Uint8List.fromList(chunk));
  }
  return out.takeBytes();
}

Uint8List _pattern(int len, [int seed = 7]) =>
    Uint8List.fromList(List<int>.generate(len, (i) => (i * 31 + seed) & 255));

void main() {
  late Directory tempDir;
  Future<String?> chooseDir(String _) async => tempDir.path;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('intragram_web_stream_io_');
  });

  tearDown(() async {
    IncomingSessionFiles.forget();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'MemoryWebByteSource copies, multi-reads, and zeros on dispose',
    () async {
      final raw = _pattern(kWebStreamChunkBytes * 2 + 137);
      final expected = Uint8List.fromList(raw);
      final source = MemoryWebByteSource(raw);
      raw.fillRange(0, raw.length, 0xAA);

      expect(source.length, expected.length);
      expect(await _collect(source.openRead()), expected);
      expect(await _collect(source.openRead()), expected);

      await source.dispose();
      expect(source.debugBuffer.every((b) => b == 0), isTrue);
      expect(() => source.openRead(), throwsStateError);
    },
  );

  test('webSourceFromPath and webSourceFromPlatformFile multi-read', () async {
    final bytes = _pattern(kWebStreamChunkBytes * 3 + 511, 13);
    final disk = File(p.join(tempDir.path, 'sample.bin'));
    await disk.writeAsBytes(bytes, flush: true);

    final pathSrc = await webSourceFromPath(disk.path);
    expect(pathSrc.length, bytes.length);
    expect(await _collect(pathSrc.openRead()), bytes);
    expect(await _collect(pathSrc.openRead()), bytes);
    await pathSrc.dispose();
    expect(await disk.exists(), isTrue);

    final filePf = _TestPlatformFile(
      'sample.bin',
      Uri.file(disk.path),
      bytes.length,
      () => throw StateError('must delegate to path'),
    );
    final pfPathSrc = await webSourceFromPlatformFile(filePf);
    expect(pfPathSrc.length, bytes.length);
    expect(await _collect(pfPathSrc.openRead()), bytes);
    expect(await _collect(pfPathSrc.openRead()), bytes);
    await pfPathSrc.dispose();

    final streamPf = _TestPlatformFile(
      'oversized.bin',
      Uri.parse('custom://memory/oversized'),
      bytes.length,
      () => Stream.fromIterable([
        Uint8List.sublistView(bytes, 0, kWebStreamChunkBytes * 2 + 19),
        Uint8List.sublistView(bytes, kWebStreamChunkBytes * 2 + 19),
      ]),
    );
    final pfStreamSrc = await webSourceFromPlatformFile(streamPf);
    expect(pfStreamSrc.length, bytes.length);
    expect(await _collect(pfStreamSrc.openRead()), bytes);
    expect(await _collect(pfStreamSrc.openRead()), bytes);
    await pfStreamSrc.dispose();
  });

  test(
    'openWebReceiveSink commits atomically and handles collisions',
    () async {
      final p1 = _pattern(kWebStreamChunkBytes * 2 + 99, 1);
      final sink1 = await openWebReceiveSink(
        'file.bin',
        p1.length,
        chooseDirectory: chooseDir,
        wanted: () => true,
      );
      expect(sink1, isNotNull);
      await sink1!.write(Uint8List.sublistView(p1, 0, 70000));
      await sink1.write(Uint8List(0));
      await sink1.write(Uint8List.sublistView(p1, 70000));
      expect(File(p.join(tempDir.path, 'file.bin')).existsSync(), isFalse);

      final path1 = await sink1.commit(wanted: () => true);
      expect(p.basename(path1!), 'file.bin');
      expect(await File(path1).readAsBytes(), p1);

      final p2 = _pattern(4096, 2);
      final sink2 = await openWebReceiveSink(
        'file.bin',
        p2.length,
        chooseDirectory: chooseDir,
        wanted: () => true,
      );
      await sink2!.write(p2);
      final path2 = await sink2.commit(wanted: () => true);
      expect(p.basename(path2!), 'file (1).bin');
      expect(await File(path1).readAsBytes(), p1);
      expect(await File(path2).readAsBytes(), p2);

      final parts = tempDir.listSync().where((e) => e.path.endsWith('.part'));
      expect(parts, isEmpty);
    },
  );

  test('openWebReceiveSink abort and !wanted leave zero .part files', () async {
    expect(
      await openWebReceiveSink(
        'skip.bin',
        128,
        chooseDirectory: chooseDir,
        wanted: () => false,
      ),
      isNull,
    );

    final aborted = await openWebReceiveSink(
      'partial.bin',
      1024,
      chooseDirectory: chooseDir,
      wanted: () => true,
    );
    await aborted!.write(_pattern(512, 5));
    await aborted.abort();
    await aborted.abort();
    expect(tempDir.listSync(), isEmpty);

    final unwanted = await openWebReceiveSink(
      'unwanted.bin',
      1024,
      chooseDirectory: chooseDir,
      wanted: () => true,
    );
    await unwanted!.write(_pattern(1024, 9));
    expect(await unwanted.commit(wanted: () => false), isNull);
    expect(tempDir.listSync(), isEmpty);
  });

  test('free-space guard, fallback memory sink, and stub checks', () async {
    await expectLater(
      () => openWebReceiveSink(
        'huge.bin',
        1024 * 1024 * 1024 * 1024 * 1024,
        chooseDirectory: chooseDir,
        wanted: () => true,
      ),
      throwsA(
        isA<StateError>().having((e) => e.message, 'm', 'insufficient-storage'),
      ),
    );
    expect(tempDir.listSync(), isEmpty);

    Uint8List? saved;
    final memSink = MemoryBufferReceiveSink((b) {
      saved = Uint8List.fromList(b);
      return 'blob:test';
    }, maxBytes: 100);
    await memSink.write(Uint8List.fromList([1, 2, 3]));
    expect(await memSink.commit(wanted: () => true), 'blob:test');
    expect(saved, [1, 2, 3]);

    final over = MemoryBufferReceiveSink((_) => 'blob:x', maxBytes: 4);
    await expectLater(() => over.write(Uint8List(5)), throwsStateError);

    expect(BrowserReceivedFiles.contains('blob:none'), isFalse);
    expect(
      () => BrowserReceivedFiles.openRead('blob:none'),
      throwsUnsupportedError,
    );
    await expectLater(
      BrowserReceivedFiles.lengthOf('blob:none'),
      throwsStateError,
    );
    await sweepWebStreamTemp();
  });
}
