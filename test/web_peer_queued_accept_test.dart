import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/network/web_peer_protocol.dart'
    show webPeerLanes, webPeerNewId;

import 'web_peer_fake.dart';

// 수락은 됐지만 자리(lane)를 기다리는 제안: 보내는 쪽에 'accepted'로 보여서 답 없는 제안과 구별됨
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
    webPeerTransferTimeout = const Duration(seconds: 30);
    await left.close();
    await right.close();
  });
  Future<void> fromRight(String kind, String id) => b.channel.send(
    RTCDataChannelMessage(jsonEncode({'kind': kind, 'id': id})),
  );

  String last(List<WebPeerTransfer> log, String id) =>
      log.lastWhere((t) => t.id == id).state;
  Iterable<String> kinds(WebPeerFakeConnection from) => from.channel.sent
      .where((m) => !m.isBinary)
      .map((m) => (jsonDecode(m.text) as Map)['kind'] as String);
  Future<List<String>> offers(int count) async {
    final batch = webPeerNewId();
    final ids = [
      for (var i = 0; i < count; i++)
        await left.offerPreparedBytes(
          '$i.bin',
          Uint8List(1 << 20),
          batch: batch,
        ),
    ];
    await webPeerUntil(() => received.map((t) => t.id).toSet().length == count);
    return ids;
  }

  test('an accept that waits for a free lane on the receiver is announced '
      'and shows as accepted on the sender until it starts', () async {
    left.peerLanes = right.peerLanes = webPeerLanes;
    final ids = await offers(4);
    // 보내는 쪽 바이트가 멈춰 있어 먼저 수락한 세 파일이 받는 쪽 자리를 차지함
    a.channel.buffer = 1 << 30;
    for (final id in ids.take(3)) {
      await right.acceptFile(id);
    }
    await right.acceptFile(ids[3]);
    expect(right.receiveLanesBusy, isTrue);
    expect(last(received, ids[3]), 'offered');
    await webPeerUntil(() => last(sent, ids[3]) == 'accepted');
    expect(kinds(b).where((k) => k == 'file-queued'), hasLength(1));

    a.channel.buffer = 0;
    await webPeerUntil(
      () => ids.every((id) => last(received, id) == 'complete'),
    );
    expect(ids.map((id) => last(sent, id)).toSet(), {'complete'});
    expect(errors, isEmpty);
  });

  test('a peer that never announced lanes is not sent the queue notice it '
      'does not know', () async {
    right.peerLanes = 1;
    left.peerLanes = webPeerLanes;
    final ids = await offers(2);
    a.channel.buffer = 1 << 30;
    await right.acceptFile(ids[0]);
    await right.acceptFile(ids[1]);
    await pumpEventQueue();
    expect(kinds(b), isNot(contains('file-queued')));
    expect(last(sent, ids[1]), 'offered');

    a.channel.buffer = 0;
    await webPeerUntil(
      () => ids.every((id) => last(received, id) == 'complete'),
    );
    expect(errors, isEmpty);
  });

  test(
    'an accept the sender itself queues behind its own lanes shows as '
    'accepted, and a repeated or late queue notice changes nothing',
    () async {
      left.peerLanes = right.peerLanes = webPeerLanes;
      final ids = await offers(4);
      a.channel.buffer = 1 << 30;
      // lanes를 지키지 않고 전부 바로 수락하는 상대 (보조 HTML 클라이언트처럼)
      for (final id in ids) {
        await b.channel.send(
          RTCDataChannelMessage(jsonEncode({'kind': 'file-accept', 'id': id})),
        );
      }
      await webPeerUntil(() => last(sent, ids[3]) == 'accepted');
      expect(ids.take(3).map((id) => last(sent, id)).toSet(), {'transferring'});
      final events = sent.length;
      for (final id in [ids[0], ids[3], ids[3], webPeerNewId()]) {
        await b.channel.send(
          RTCDataChannelMessage(jsonEncode({'kind': 'file-queued', 'id': id})),
        );
      }
      await pumpEventQueue();
      // 흐르는 전송·모르는 id의 알림은 무시하고, 기다리는 제안엔 한 번만 반영함 (상태는 이미 accepted)
      expect(sent.length, events + 1);
      expect(left.state, 'connected');
      expect(errors, isEmpty);
    },
  );

  // 줄 세웠다는 알림만 보내고 아무것도 수락하지 않는 상대가 제안을 '수락됨'으로 바꿔 송신 예산을 붙잡지 못함
  test('a queue notice while none of our transfers is in flight is ignored: '
      'the offer stays unanswered', () async {
    left.peerLanes = right.peerLanes = webPeerLanes;
    final ids = await offers(2);
    for (final id in ids) {
      await fromRight('file-queued', id);
    }
    await pumpEventQueue();
    expect(ids.map((id) => last(sent, id)).toSet(), {'offered'});
    expect(left.state, 'connected');
    expect(errors, isEmpty);
  });

  test('a queued offer counts as unanswered again when our transfers in '
      'flight ended and the peer still has not accepted it', () async {
    webPeerTransferTimeout = const Duration(milliseconds: 200);
    left.peerLanes = right.peerLanes = webPeerLanes;
    final ids = await offers(3);
    // 원시 프레임만 주입함: 수락된 전송의 바이트는 흐르지 않게 막아 둠
    a.channel.buffer = 1 << 30;
    await fromRight('file-accept', ids[0]);
    await webPeerUntil(() => last(sent, ids[0]) == 'transferring');
    await fromRight('file-queued', ids[1]);
    await fromRight('file-queued', ids[2]);
    await webPeerUntil(
      () => ids.skip(1).every((id) => last(sent, id) == 'accepted'),
    );
    // 흐르던 전송이 끝남(상대가 취소). 줄 세운 제안은 잠시 그대로였다가, 수락이 끝내 안 오면 되돌아감
    await fromRight('file-cancel', ids[0]);
    await webPeerUntil(() => last(sent, ids[0]) == 'cancelled');
    expect(ids.skip(1).map((id) => last(sent, id)).toSet(), {'accepted'});
    await webPeerUntil(
      () => ids.skip(1).every((id) => last(sent, id) == 'offered'),
    );
    // 되돌아간 뒤에도 진짜 수락은 그대로 받음
    await fromRight('file-accept', ids[1]);
    await webPeerUntil(() => last(sent, ids[1]) == 'transferring');
    expect(left.state, 'connected');
  });
}
