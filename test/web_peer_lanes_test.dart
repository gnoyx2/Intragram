import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/network/web_peer_protocol.dart'
    show webPeerLanes, webPeerNewId, webPeerValidateControl;
import 'package:intragram/network/web_stream_io.dart'
    show MemoryWebByteSource, WebReceiveSink;
import 'package:intragram/store/models.dart';

import 'support/web_chat_rig.dart';
import 'web_peer_fake.dart';

class _Sink implements WebReceiveSink {
  final bytes = BytesBuilder();
  @override
  Future<void> write(Uint8List chunk) async => bytes.add(chunk);
  @override
  Future<String?> commit({required bool Function() wanted}) async => 'saved';
  @override
  Future<void> abort() async {}
}

// 동시에 transferring인 전송 수의 최댓값
int _peak(List<WebPeerTransfer> log) {
  final open = <String>{};
  var peak = 0;
  for (final t in log) {
    t.state == 'transferring' ? open.add(t.id) : open.remove(t.id);
    if (open.length > peak) peak = open.length;
  }
  return peak;
}

void main() {
  late WebPeerSession left, right;
  late WebPeerFakeConnection a, b;
  late List<WebPeerTransfer> sent, received;
  late List<Object> errors;
  setUp(() async {
    a = WebPeerFakeConnection('AA');
    b = WebPeerFakeConnection('BB');
    a.channel.peer = b.channel;
    b.channel.peer = a.channel;
    sent = [];
    received = [];
    errors = [];
    left = WebPeerSession(
      connectionFactory: (_) async => a,
      onTransfer: sent.add,
      onError: errors.add,
    );
    right = WebPeerSession(
      connectionFactory: (_) async => b,
      onTransfer: received.add,
      onError: errors.add,
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
  });

  String last(List<WebPeerTransfer> log, String id) =>
      log.lastWhere((t) => t.id == id).state;
  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  test(
    'with lanes a small file accepted after a big one overtakes it',
    () async {
      left.peerLanes = right.peerLanes = webPeerLanes;
      final big = await left.offerPreparedBytes('big.bin', Uint8List(4 << 20));
      final small = await left.offerPreparedBytes('small.txt', bytes('작은 파일'));
      await webPeerUntil(() => received.map((t) => t.id).toSet().length == 2);
      await right.acceptFile(big);
      await right.acceptFile(small);
      await webPeerUntil(() => last(received, big) == 'complete');
      final done = received
          .where((t) => t.state == 'complete')
          .map((t) => t.id);
      expect(done, [small, big]);
      expect(received.lastWhere((t) => t.id == small).bytes, bytes('작은 파일'));
      expect(received.lastWhere((t) => t.id == big).bytes, Uint8List(4 << 20));
      expect(errors, isEmpty);
    },
  );

  test(
    'the receiver runs at most three at once, the rest wait their turn',
    () async {
      left.peerLanes = right.peerLanes = webPeerLanes;
      final batch = webPeerNewId();
      final ids = [
        for (var i = 0; i < 4; i++)
          await left.offerPreparedBytes(
            '$i.bin',
            Uint8List(1 << 20),
            batch: batch,
          ),
      ];
      final sink = _Sink();
      final stream = await left.offerStream(
        'stream.txt',
        MemoryWebByteSource(bytes('stream 스트림')),
        batch: batch,
      );
      await webPeerUntil(() => received.map((t) => t.id).toSet().length == 5);
      for (final id in ids) {
        await right.acceptFile(id);
      }
      await right.acceptFileStream(stream, sink, wanted: () => true);
      expect(right.receiveLanesBusy, isTrue);
      await webPeerUntil(
        () => [...ids, stream].every((id) => last(received, id) == 'complete'),
      );
      expect(_peak(received), webPeerLanes);
      expect(_peak(sent), webPeerLanes);
      expect(utf8.decode(sink.bytes.takeBytes()), 'stream 스트림');
      final starts = received
          .where((t) => t.state == 'transferring')
          .map((t) => t.id);
      expect(starts.toSet().take(3), ids.take(3), reason: 'accept order');
      expect(errors, isEmpty);
    },
  );

  test(
    'a sender queues accepts beyond its own lanes instead of dropping them',
    () async {
      left.peerLanes = webPeerLanes;
      right.peerLanes = 8;
      final ids = [
        for (var i = 0; i < 5; i++)
          await left.offerPreparedBytes('$i.bin', Uint8List(512 << 10)),
      ];
      await webPeerUntil(() => received.map((t) => t.id).toSet().length == 5);
      for (final id in ids) {
        await right.acceptFile(id);
      }
      await webPeerUntil(
        () => ids.every((id) => last(received, id) == 'complete'),
      );
      expect(_peak(sent), webPeerLanes);
      expect(ids.map((id) => last(sent, id)).toSet(), {'complete'});
      expect(errors, isEmpty);
    },
  );

  test(
    'a peer that never announced lanes still gets one file at a time',
    () async {
      right.peerLanes = webPeerLanes;
      final one = await left.offerPreparedBytes('a.bin', Uint8List(1 << 20));
      await expectLater(
        left.offerPreparedBytes('b.txt', bytes('b')),
        throwsA(isA<WebPeerProblem>()),
      );
      await right.acceptFile(one);
      await webPeerUntil(() => last(received, one) == 'complete');
      expect(_peak(sent), 1);
    },
  );

  test('lanes in capabilities must be a small positive integer', () {
    for (final lanes in [1, webPeerLanes, 8]) {
      webPeerValidateControl({
        'k': 'native-room',
        'frame': {'k': 'capabilities', 'v': 1, 'batch': true, 'lanes': lanes},
      });
    }
    for (final lanes in [0, 9, -1, '3', 2.5]) {
      expect(
        () => webPeerValidateControl({
          'k': 'native-room',
          'frame': {'k': 'capabilities', 'v': 1, 'lanes': lanes},
        }),
        throwsA(isA<WebPeerProblem>()),
      );
    }
  });

  test(
    'two app peers offer separate files at once and receive them in parallel',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final inbox = Directory.systemTemp.createTempSync('web-lanes-in-');
      final outbox = Directory.systemTemp.createTempSync('web-lanes-out-');
      final host = await WebChatRig.create('CC', directory: inbox.path);
      final guest = await WebChatRig.create('DD', directory: inbox.path);
      addTearDown(() async {
        await host.dispose();
        await guest.dispose();
        inbox.deleteSync(recursive: true);
        outbox.deleteSync(recursive: true);
      });
      await host.connect(guest);
      await webPeerUntil(
        () =>
            host.sessions.single.peerLanes == webPeerLanes &&
            guest.sessions.single.peerLanes == webPeerLanes,
      );
      final big = File('${outbox.path}/big.bin')
        ..writeAsBytesSync(Uint8List(3 << 20));
      final small = File('${outbox.path}/small.txt')
        ..writeAsStringSync('small');
      await host.bridge.offerPaths(host.room!, [big.path]);
      await host.bridge.offerPaths(host.room!, [small.path]);
      List<FileTransfer> offered() => guest.store.transfers
          .where((t) => t.direction == TransferDirection.incoming)
          .toList();
      await webPeerUntil(() => offered().length == 2);
      expect(offered().map((t) => t.batchId).toSet(), {null});
      for (final t in offered()) {
        await guest.bridge.accept(t.id);
      }
      await webPeerUntil(
        () => offered().every((t) => t.state == TransferState.complete),
      );
      expect(File('${inbox.path}/small.txt').readAsStringSync(), 'small');
      expect(File('${inbox.path}/big.bin').lengthSync(), 3 << 20);
    },
  );
}
