import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/network/web_stream_io.dart';

import 'web_peer_fake.dart';

// 최종 파일을 만든 뒤(wanted 마지막 확인 다음) 테스트가 풀어 줄 때까지 커밋을 끝내지 않음:
// 이름 바꾸기·Zone.Identifier·OPFS getFile 사이에 취소가 끼는 창
class _FileCommitSink implements WebReceiveSink {
  _FileCommitSink(this.file);
  final File file;
  final committed = Completer<void>(), release = Completer<void>();
  @override
  Future<void> write(Uint8List chunk) async {}
  @override
  Future<String?> commit({required bool Function() wanted}) async {
    if (!wanted()) return null;
    file.writeAsStringSync('received');
    committed.complete();
    await release.future;
    return file.path;
  }

  @override
  Future<void> abort() async {}
}

void main() {
  late WebPeerSession left, right;
  late WebPeerFakeConnection a, b;
  late List<WebPeerTransfer> sent, received;
  late Directory dir;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('web-commit-cancel-');
    a = WebPeerFakeConnection('AA');
    b = WebPeerFakeConnection('BB');
    a.channel.peer = b.channel;
    b.channel.peer = a.channel;
    sent = [];
    received = [];
    left = WebPeerSession(
      connectionFactory: (_) async => a,
      onTransfer: sent.add,
    );
    right = WebPeerSession(
      connectionFactory: (_) async => b,
      onTransfer: received.add,
    );
    final answer = await right.acceptOffer(await left.createOffer());
    b.onDataChannel!(b.channel);
    await left.acceptAnswer(answer);
    a.channel.open();
    b.channel.open();
    await webPeerUntil(
      () => left.state == 'connected' && right.state == 'connected',
    );
  });
  tearDown(() async {
    await left.close();
    await right.close();
    dir.deleteSync(recursive: true);
  });

  Future<_FileCommitSink> committing() async {
    final id = await left.offerStream(
      'photo.jpg',
      MemoryWebByteSource(Uint8List(96 * 1024)),
    );
    await webPeerUntil(() => received.isNotEmpty);
    final sink = _FileCommitSink(File('${dir.path}/photo.jpg'));
    await right.acceptFileStream(id, sink, wanted: () => true);
    await sink.committed.future;
    return sink;
  }

  test('a receiver cancel during commit leaves no file behind', () async {
    final sink = await committing();
    await right.cancelFile(received.last.id);
    sink.release.complete();
    await webPeerUntil(() => sent.last.state == 'cancelled');
    await webPeerUntil(() => !sink.file.existsSync());
    expect(received.last.state, 'cancelled');
    expect(right.state, 'connected');
  });

  test('a sender cancel during commit leaves no file behind', () async {
    final sink = await committing();
    await left.cancelFile(sent.last.id);
    await webPeerUntil(() => received.last.state == 'cancelled');
    sink.release.complete();
    await webPeerUntil(() => !sink.file.existsSync());
    expect(sent.last.state, 'cancelled');
  });

  test('a link that closes during commit leaves no file behind', () async {
    final sink = await committing();
    await right.close();
    sink.release.complete();
    await webPeerUntil(() => !sink.file.existsSync());
    expect(received.last.state, 'failed');
  });

  test('an undisturbed commit keeps the file and completes', () async {
    final sink = await committing();
    sink.release.complete();
    await webPeerUntil(() => sent.last.state == 'complete');
    expect(received.last.state, 'complete');
    expect(received.last.localPath, sink.file.path);
    expect(sink.file.readAsStringSync(), 'received');
  });
}
