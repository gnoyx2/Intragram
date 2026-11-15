import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/web_stream_io.dart';

// 이 프로세스가 dir 안 파일을 아직 열고 있는지 (지운 뒤에도 열린 fd는 디스크 공간을 쥠)
bool _holdsFileIn(Directory dir) =>
    (Process.runSync('lsof', ['-p', '$pid', '-Fn']).stdout as String)
        .split('\n')
        .any((line) => line.contains(dir.path.split('/').last));

final _hasLsof =
    !Platform.isWindows &&
    Process.runSync('sh', ['-c', 'command -v lsof']).exitCode == 0;

void main() {
  // 취소는 대개 64 KiB 쓰기 도중에 옴: 쓰기가 끝난 뒤 닫아야 fd와 .part가 남지 않음
  test(
    'abort during an in-flight write closes the file and removes the part',
    () async {
      final dir = Directory.systemTemp.createTempSync('web-sink-abort-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final sink = await openWebReceiveSink(
        'abort.bin',
        64 * 1024 * 1024,
        chooseDirectory: (_) async => dir.path,
        wanted: () => true,
      );
      final writing = sink!.write(Uint8List(32 * 1024 * 1024));
      await sink.abort();
      await writing.catchError((Object _) {});
      expect(_holdsFileIn(dir), isFalse, reason: 'receive file left open');
      expect(dir.listSync(), isEmpty);
    },
    skip: !_hasLsof,
  );
}
