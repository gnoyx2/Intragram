import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intragram/core/constants.dart'
    show kFrameCeilingBytes, kMaxFrameBytes;
import 'package:intragram/core/path_safety.dart' show safeBasename;
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/network/web_peer_protocol.dart';
import 'package:intragram/network/web_stream_io.dart';

import 'web_peer_fake.dart';

// 큰 파일의 flush·fsync처럼 오래 걸리는 커밋
class _SlowSink implements WebReceiveSink {
  bool? wantedAtCommit;
  @override
  Future<void> write(Uint8List chunk) async {}
  @override
  Future<String?> commit({required bool Function() wanted}) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    wantedAtCommit = wanted();
    return wantedAtCommit! ? 'saved' : null;
  }

  @override
  Future<void> abort() async {}
}

// 쓰기를 막아 둠: 보내는 쪽이 credit에 묶여 전송이 중간에 머무름
class _BlockedSink implements WebReceiveSink {
  final _release = Completer<void>();
  @override
  Future<void> write(Uint8List chunk) => _release.future;
  @override
  Future<String?> commit({required bool Function() wanted}) async =>
      wanted() ? 'saved' : null;
  @override
  Future<void> abort() async {
    if (!_release.isCompleted) _release.complete();
  }
}

// 받은 바이트를 다 쓴 뒤 저장(이름 바꾸기·fsync)에서 실패: 디스크 꽉 참, 폴더 분리
class _FailingCommitSink implements WebReceiveSink {
  @override
  Future<void> write(Uint8List chunk) async {}
  @override
  Future<String?> commit({required bool Function() wanted}) async =>
      throw StateError('insufficient-storage');
  @override
  Future<void> abort() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WebPeerSession left, right;
  late WebPeerFakeConnection a, b;
  late List<WebPeerTransfer> sent, received;
  late List<Object> errors;
  late List<String> texts;

  setUp(() async {
    a = WebPeerFakeConnection('AA');
    b = WebPeerFakeConnection('BB');
    a.channel.peer = b.channel;
    b.channel.peer = a.channel;
    sent = [];
    received = [];
    errors = [];
    texts = [];
    left = WebPeerSession(
      connectionFactory: (_) async => a,
      onTransfer: sent.add,
    );
    right = WebPeerSession(
      connectionFactory: (_) async => b,
      onTransfer: received.add,
      onMessage: texts.add,
      onError: errors.add,
    );
    final offer = await left.createOffer();
    final answer = await right.acceptOffer(offer);
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
  });

  void deliver(Uint8List binary) =>
      b.channel.onMessage?.call(RTCDataChannelMessage.fromBinary(binary));

  test('a stream chunk still on the wire after the receiver cancels keeps the '
      'link open', () async {
    const size = 8 * 1024 * 1024;
    final source = MemoryWebByteSource(Uint8List(size));
    final id = await left.offerStream('big.bin', source);
    await webPeerUntil(() => received.isNotEmpty);
    await right.acceptFileStream(id, _BlockedSink(), wanted: () => true);
    await webPeerUntil(() => received.last.transferred >= 1024 * 1024);
    // Still mid-stream: the sender waits for credit the blocked sink never grants.
    expect(received.last.state, 'transferring');
    expect(received.last.transferred, lessThan(size));
    await right.cancelFile(id);
    expect(received.last.state, 'cancelled');
    // The sender queued this 64 KiB chunk before it saw file-cancel.
    deliver(webPeerMakeStreamChunk(id, 1024 * 1024, Uint8List(64 * 1024)));
    // A small chunk for a transfer nobody is receiving is dropped as well.
    deliver(webPeerMakeChunk(id, 0, Uint8List(16)));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(right.state, 'connected');
    expect(errors, isEmpty);
    await left.sendText('still connected');
    await webPeerUntil(() => texts.contains('still connected'));
  });

  // v7 제안과 같이 서식 문자(RLO 등)로 확장자를 위장한 이름을 정제함
  test('offered file names are cleaned like native v7 offers', () async {
    const spoofed = 'invoice\u202Efdp.exe';
    await left.offerBytes(spoofed, Uint8List(4));
    await webPeerUntil(() => received.isNotEmpty);
    expect(received.last.name, 'invoicefdp.exe');
    expect(received.last.name, safeBasename(spoofed));
  });

  // v7처럼 받는 쪽 설정(inline·spill 2 MiB)을 넘는 다중 파트는 모으기 전에 끊음
  test(
    'multi-part text above the receiver cap is refused at its first part',
    () async {
      right.maxReassembledBytes = () => kMaxFrameBytes;
      final fits = 'f' * (kMaxFrameBytes - 1024);
      await left.sendText(fits, maxBytes: kFrameCeilingBytes);
      await webPeerUntil(() => texts.contains(fits));
      await left.sendText(
        'o' * (kMaxFrameBytes + 1),
        maxBytes: kFrameCeilingBytes,
      );
      await webPeerUntil(() => right.state == 'closed');
      expect(errors.map((e) => '$e'), contains(contains('invalid-frame')));
      expect(texts, hasLength(1));
    },
  );

  // 동시에 보낸 긴 메시지 둘: 파트가 섞이면 받는 쪽 진행 중 합계가 상한(2 MiB)을 넘어 링크가 끊겼음
  test(
    'two long texts sent at once both arrive under the inline cap',
    () async {
      right.maxReassembledBytes = () => kMaxFrameBytes;
      final first = 'a' * 1100000, second = 'b' * 1100000;
      await Future.wait([
        left.sendText(first, maxBytes: kFrameCeilingBytes),
        left.sendText(second, maxBytes: kFrameCeilingBytes),
      ]);
      await webPeerUntil(() => texts.length == 2);
      expect(texts, [first, second]);
      expect(right.state, 'connected');
      expect(errors, isEmpty);
    },
  );

  Future<(String, _SlowSink)> receiveIntoSlowSink() async {
    final id = await left.offerStream(
      'slow.bin',
      MemoryWebByteSource(Uint8List(200 * 1024)),
    );
    await webPeerUntil(() => received.isNotEmpty);
    final sink = _SlowSink();
    await right.acceptFileStream(id, sink, wanted: () => true);
    await webPeerUntil(() => received.last.transferred == 200 * 1024);
    return (id, sink);
  }

  test(
    'a cancel while the receiver commits keeps no file and no done',
    () async {
      final (id, sink) = await receiveIntoSlowSink();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await right.cancelFile(id);
      await webPeerUntil(() => sink.wantedAtCommit != null);
      expect(sink.wantedAtCommit, isFalse);
      await webPeerUntil(() => sent.last.state == 'cancelled');
      expect(received.last.state, 'cancelled');
    },
  );

  test(
    'a slow commit completes on both sides: neither deadline cancels it',
    () async {
      final savedTimeout = webPeerTransferTimeout;
      final savedRate = webPeerCommitBytesPerSecond;
      webPeerTransferTimeout = const Duration(milliseconds: 250);
      // 200 KiB at 100 KiB/s: the sender waits 2 s more for file-done.
      webPeerCommitBytesPerSecond = 100 * 1024;
      addTearDown(() {
        webPeerTransferTimeout = savedTimeout;
        webPeerCommitBytesPerSecond = savedRate;
      });
      final (_, sink) = await receiveIntoSlowSink();
      await webPeerUntil(() => sink.wantedAtCommit != null);
      expect(sink.wantedAtCommit, isTrue);
      await webPeerUntil(() => sent.last.state == 'complete');
      expect(received.last.state, 'complete');
      expect(right.state, 'connected');
    },
  );

  test('a commit failure fails only that file and keeps the link', () async {
    final id = await left.offerStream(
      'full.bin',
      MemoryWebByteSource(Uint8List(200 * 1024)),
    );
    await webPeerUntil(() => received.isNotEmpty);
    await right.acceptFileStream(id, _FailingCommitSink(), wanted: () => true);
    await webPeerUntil(() => received.last.state == 'failed');
    await webPeerUntil(() => sent.last.state == 'cancelled');
    expect(right.state, 'connected');
    expect(errors.map((e) => '$e'), contains(contains('insufficient-storage')));
    await left.sendText('still connected');
    await webPeerUntil(() => texts.contains('still connected'));
  });

  test(
    'a binary frame above the stream chunk bound still closes the link',
    () async {
      deliver(Uint8List(webPeerStreamChunkBytes + 25));
      await webPeerUntil(() => right.state == 'closed');
      expect(errors.map((e) => '$e'), contains(contains('invalid-frame')));
    },
  );
}
