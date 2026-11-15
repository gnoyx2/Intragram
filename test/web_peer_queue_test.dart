import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/network/web_peer_protocol.dart'
    show webPeerMaxWaitingOffers, webPeerNewId;
import 'package:intragram/network/web_stream_io.dart'
    show MemoryWebByteSource, WebReceiveSink;

import 'web_peer_fake.dart';

class _Sink implements WebReceiveSink {
  final bytes = BytesBuilder();
  bool aborted = false;
  @override
  Future<void> write(Uint8List chunk) async => bytes.add(chunk);
  @override
  Future<String?> commit({required bool Function() wanted}) async => 'saved';
  @override
  Future<void> abort() async => aborted = true;
}

void main() {
  late WebPeerSession left, right;
  late WebPeerFakeConnection a, b;
  late List<WebPeerTransfer> sent, received;
  late List<Object> errors;
  setUp(() {
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
  });
  tearDown(() async {
    await left.close();
    await right.close();
  });
  Future<void> connect() async {
    final answer = await right.acceptOffer(await left.createOffer());
    b.onDataChannel!(b.channel);
    await left.acceptAnswer(answer);
    a.channel.open();
    b.channel.open();
    await webPeerUntil(
      () => left.state == 'connected' && right.state == 'connected',
    );
  }

  String last(List<WebPeerTransfer> log, String id) =>
      log.lastWhere((t) => t.id == id).state;
  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  test(
    'a batch keeps every offer pending and runs the chosen ones in order',
    () async {
      await connect();
      final batch = webPeerNewId();
      final one = await left.offerPreparedBytes(
        'a.txt',
        bytes('first'),
        batch: batch,
      );
      final two = await left.offerPreparedBytes(
        'b.txt',
        bytes('second'),
        batch: batch,
      );
      final three = await left.offerStream(
        'c.txt',
        MemoryWebByteSource(bytes('third 세번째')),
        batch: batch,
      );
      await webPeerUntil(() => received.map((t) => t.id).toSet().length == 3);
      expect(received.map((t) => t.batch).toSet(), {batch});
      expect(received.map((t) => t.state).toSet(), {'offered'});
      expect(a.channel.sent.where((m) => m.isBinary), isEmpty);

      // The third file is picked first: it overtakes the undecided first offer.
      final sink = _Sink();
      await right.acceptFileStream(three, sink, wanted: () => true);
      await webPeerUntil(() => last(received, three) == 'complete');
      expect(utf8.decode(sink.bytes.takeBytes()), 'third 세번째');
      await right.acceptFile(one);
      await webPeerUntil(() => last(received, one) == 'complete');
      expect(received.lastWhere((t) => t.id == one).bytes, bytes('first'));
      await right.rejectFile(two);
      await webPeerUntil(() => last(sent, two) == 'rejected');
      expect([one, three].map((id) => last(sent, id)), [
        'complete',
        'complete',
      ]);
      expect(errors, isEmpty);
    },
  );

  test('an accept made while another file flows waits for its turn', () async {
    await connect();
    final batch = webPeerNewId();
    final one = await left.offerPreparedBytes(
      'big.bin',
      Uint8List(200 * 1024),
      batch: batch,
    );
    final two = await left.offerPreparedBytes(
      'small.txt',
      bytes('next'),
      batch: batch,
    );
    await webPeerUntil(() => received.map((t) => t.id).toSet().length == 2);
    await right.acceptFile(one);
    expect(right.receiveLanesBusy, isTrue);
    await right.acceptFile(two);
    await webPeerUntil(() => last(received, two) == 'complete');
    final order = received.where((t) => t.state == 'complete').map((t) => t.id);
    expect(order, [one, two]);
    expect(received.lastWhere((t) => t.id == two).bytes, bytes('next'));
  });

  test(
    'accepts made while a file flows start in the order they were made',
    () async {
      await connect();
      final batch = webPeerNewId();
      final big = await left.offerPreparedBytes(
        'big.bin',
        Uint8List(400 * 1024),
        batch: batch,
      );
      final two = await left.offerPreparedBytes(
        '2.txt',
        bytes('2'),
        batch: batch,
      );
      final three = await left.offerPreparedBytes(
        '3.txt',
        bytes('3'),
        batch: batch,
      );
      await webPeerUntil(() => received.map((t) => t.id).toSet().length == 3);
      await right.acceptFile(big);
      await right.acceptFile(three);
      await right.acceptFile(two);
      await webPeerUntil(() => last(received, two) == 'complete');
      final order = received
          .where((t) => t.state == 'complete')
          .map((t) => t.id);
      expect(order, [big, three, two]);
    },
  );

  test(
    'unbatched offers still refuse a second offer while one is open',
    () async {
      await connect();
      await left.offerPreparedBytes('x.txt', bytes('x'));
      await expectLater(
        left.offerPreparedBytes('y.txt', bytes('y')),
        throwsA(isA<WebPeerProblem>()),
      );
    },
  );

  test(
    'the receiver caps waiting offers and rejects a malformed batch id',
    () async {
      await connect();
      final ids = [
        for (var i = 0; i <= webPeerMaxWaitingOffers + 1; i++) webPeerNewId(),
      ];
      for (final id in ids) {
        b.channel.onMessage!(
          RTCDataChannelMessage(
            jsonEncode({
              'kind': 'file-offer',
              'id': id,
              'name': 'f.txt',
              'size': 1,
            }),
          ),
        );
      }
      await webPeerUntil(
        () =>
            b.channel.sent.any((m) => !m.isBinary && m.text.contains(ids.last)),
      );
      expect(jsonDecode(b.channel.sent.last.text), {
        'kind': 'file-reject',
        'id': ids.last,
      });
      expect(
        received.map((t) => t.id).toSet().length,
        webPeerMaxWaitingOffers + 1,
      );
      b.channel.onMessage!(
        RTCDataChannelMessage(
          jsonEncode({
            'kind': 'file-offer',
            'id': webPeerNewId(),
            'name': 'g.txt',
            'size': 1,
            'bid': 'not-an-id',
          }),
        ),
      );
      await webPeerUntil(() => right.state == 'closed');
      expect(
        errors.whereType<WebPeerProblem>().map((e) => e.code),
        contains('invalid-frame'),
      );
    },
  );

  test('closing drops a deferred accept and its open sink', () async {
    await connect();
    final batch = webPeerNewId();
    final one = await left.offerPreparedBytes(
      'a.bin',
      Uint8List(200 * 1024),
      batch: batch,
    );
    final two = await left.offerStream(
      'b.bin',
      MemoryWebByteSource(bytes('later')),
      batch: batch,
    );
    await webPeerUntil(() => received.map((t) => t.id).toSet().length == 2);
    await right.acceptFile(one);
    final sink = _Sink();
    await right.acceptFileStream(two, sink, wanted: () => true);
    await right.close();
    expect(sink.aborted, isTrue);
    expect(last(received, two), 'failed');
  });
}
