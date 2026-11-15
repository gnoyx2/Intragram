import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/network/web_peer_protocol.dart' show webPeerMakeChunk;

import 'web_peer_fake.dart';

void main() {
  late WebPeerSession left, right;
  late WebPeerFakeConnection a, b;
  late List<WebPeerTransfer> sent, received;
  late List<Map<String, dynamic>> texts, controls;
  late List<Object> errors;
  setUp(() {
    a = WebPeerFakeConnection('AA');
    b = WebPeerFakeConnection('BB');
    a.channel.peer = b.channel;
    b.channel.peer = a.channel;
    sent = [];
    received = [];
    texts = [];
    controls = [];
    errors = [];
    left = WebPeerSession(
      connectionFactory: (config) async {
        a.config = config;
        return a;
      },
      onTransfer: sent.add,
      onError: errors.add,
    );
    right = WebPeerSession(
      connectionFactory: (config) async {
        b.config = config;
        return b;
      },
      onTransfer: received.add,
      onTextFrame: texts.add,
      onControl: controls.add,
      onError: errors.add,
    );
  });
  tearDown(() async {
    await left.close();
    await right.close();
  });
  Future<void> connect() async {
    final offer = await left.createOffer();
    final answer = await right.acceptOffer(offer);
    b.onDataChannel!(b.channel);
    await left.acceptAnswer(answer);
    a.channel.open();
    b.channel.open();
    await webPeerUntil(
      () => left.state == 'connected' && right.state == 'connected',
    );
  }

  test(
    'host-only empty ICE config, equal SAS, text IDs, replay and controls',
    () async {
      await connect();
      expect(a.config!['iceServers'], isEmpty);
      expect(b.config!['iceServers'], isEmpty);
      expect(left.verificationCode, matches(RegExp(r'^\d{6}$')));
      expect(left.verificationCode, right.verificationCode);
      final id = await left.sendText('한글 <b>literal</b>');
      await webPeerUntil(() => texts.isNotEmpty);
      expect(texts.single, {'id': id, 'text': '한글 <b>literal</b>'});
      b.channel.onMessage!(
        RTCDataChannelMessage(
          jsonEncode({'kind': 'text', 'id': id, 'text': 'replay'}),
        ),
      );
      expect(texts.length, 1);
      await left.sendControl({'k': 'typing', 'on': true});
      await webPeerUntil(() => controls.isNotEmpty);
      expect(controls.single, {'k': 'typing', 'on': true});
      await expectLater(
        left.sendControl({'k': 'unknown'}),
        throwsA(isA<WebPeerProblem>()),
      );
      expect(errors, isEmpty);
    },
  );
  test(
    'multi-chunk file exact bytes, empty file, consent and ACK completion',
    () async {
      await connect();
      final bytes = Uint8List.fromList(List.generate(100037, (i) => i % 251));
      final id = await left.offerBytes('한글.bin', bytes);
      await webPeerUntil(() => received.isNotEmpty);
      expect(a.channel.sent.where((f) => f.isBinary), isEmpty);
      expect(received.single.state, 'offered');
      await right.acceptFile(id);
      await webPeerUntil(
        () =>
            sent.last.state == 'complete' && received.last.state == 'complete',
      );
      expect(received.last.bytes, bytes);
      expect(sent.last.transferred, bytes.length);
      final emptyId = await left.offerBytes('empty', Uint8List(0));
      await webPeerUntil(() => received.last.id == emptyId);
      await right.acceptFile(emptyId);
      await webPeerUntil(
        () =>
            sent.last.state == 'complete' && received.last.state == 'complete',
      );
      expect(received.last.bytes, isEmpty);
      expect(errors, isEmpty);
    },
  );
  test('decline, cancel, active-transfer limit and clean close', () async {
    await connect();
    final id = await left.offerBytes('decline.bin', Uint8List(10));
    await webPeerUntil(() => received.isNotEmpty);
    await expectLater(
      left.offerBytes('busy.bin', Uint8List(1)),
      throwsA(isA<WebPeerProblem>()),
    );
    await right.rejectFile(id);
    await webPeerUntil(() => sent.last.state == 'rejected');
    final cancelId = await left.offerBytes('cancel.bin', Uint8List(10));
    await webPeerUntil(() => received.last.id == cancelId);
    await left.cancelFile(cancelId);
    await webPeerUntil(() => received.last.state == 'cancelled');
    final closeId = await left.offerBytes('close.bin', Uint8List(10));
    await webPeerUntil(() => received.last.id == closeId);
    await left.close();
    expect(sent.last.state, 'failed');
    expect(left.state, 'closed');
    expect(left.verificationCode, isEmpty);
    expect(a.closed && a.disposed, true);
    await left.close();
    await expectLater(left.sendText('late'), throwsA(isA<WebPeerProblem>()));
  });
  test('malformed offset and false early receipt close the session', () async {
    await connect();
    final id = await left.offerBytes('wrong.bin', Uint8List(100));
    await webPeerUntil(() => received.isNotEmpty);
    await right.acceptFile(id);
    // The forged ACK precedes actual end of the sender's authenticated file stream.
    a.channel.onMessage!(
      RTCDataChannelMessage(jsonEncode({'kind': 'file-done', 'id': id})),
    );
    await webPeerUntil(() => left.state == 'closed');
    expect(
      errors.any(
        (e) => e is WebPeerProblem && e.code == 'invalid-file-receipt',
      ),
      true,
    );
  });
  test(
    'close interrupts gathering and late factory creation disposes peer',
    () async {
      final pending = Completer<RTCPeerConnection>();
      final session = WebPeerSession(connectionFactory: (_) => pending.future);
      final offer = session.createOffer();
      final result = expectLater(offer, throwsA(isA<WebPeerProblem>()));
      await session.close();
      pending.complete(a);
      await result;
      expect(a.closed && a.disposed, true);
      expect(session.state, 'closed');
    },
  );
  test(
    'invalid invitation leaves idle and close cancels stalled ICE gathering',
    () async {
      await expectLater(
        left.acceptOffer('bad'),
        throwsA(isA<WebPeerProblem>()),
      );
      expect(left.state, 'idle');
      a.gathering = RTCIceGatheringState.RTCIceGatheringStateGathering;
      final offer = left.createOffer();
      final result = expectLater(offer, throwsA(isA<WebPeerProblem>()));
      await webPeerUntil(() => a.local != null);
      await left.close();
      await result;
      expect(left.state, 'closed');
    },
  );
  test('data arriving during asynchronous fingerprint is buffered', () async {
    final offer = await left.createOffer();
    final answer = await right.acceptOffer(offer);
    b.onDataChannel!(b.channel);
    await left.acceptAnswer(answer);
    a.channel.open();
    b.channel.open();
    b.channel.onMessage!(
      RTCDataChannelMessage(
        jsonEncode({'kind': 'text', 'id': 'a' * 32, 'text': 'early'}),
      ),
    );
    await webPeerUntil(() => right.state == 'connected');
    expect(texts.single['text'], 'early');
  });
  test(
    'wrong file offset fails closed, and backpressure can be cancelled',
    () async {
      await connect();
      a.channel.buffer = 1024 * 1024;
      final id = await left.offerBytes('offset.bin', Uint8List(100));
      await webPeerUntil(() => received.isNotEmpty);
      await right.acceptFile(id);
      b.channel.onMessage!(
        RTCDataChannelMessage.fromBinary(webPeerMakeChunk(id, 1, Uint8List(1))),
      );
      await webPeerUntil(() => right.state == 'closed');
      expect(
        errors.any((e) => e is WebPeerProblem && e.code == 'invalid-file-data'),
        true,
      );
      await left.close();
      expect(sent.last.state, 'failed');
    },
  );
  test(
    'a second negotiation attempt cannot destroy the waiting invitation',
    () async {
      final offer = await left.createOffer();
      await expectLater(left.createOffer(), throwsA(isA<WebPeerProblem>()));
      await expectLater(
        left.acceptOffer(offer),
        throwsA(isA<WebPeerProblem>()),
      );
      expect(left.state, 'waiting');
      expect(a.closed, false);
    },
  );
}
