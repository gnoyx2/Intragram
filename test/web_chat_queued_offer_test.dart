import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/store/models.dart';
import 'support/web_chat_rig.dart';
import 'web_peer_fake.dart';

// 받는 쪽이 수락했지만 자리가 없어 기다리는 제안은 '답 없는 제안'이 아님: 예산이 차도 취소하지 않음
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WebChatRig host, guest;
  late Directory inbox;
  setUp(() async {
    inbox = Directory.systemTemp.createTempSync('web-queued-in-');
    host = await WebChatRig.create('AA', directory: inbox.path);
    guest = await WebChatRig.create('BB', directory: inbox.path);
    await host.connect(guest);
  });
  tearDown(() async {
    webChatStaleOfferAge = const Duration(minutes: 2);
    await host.dispose();
    await guest.dispose();
    inbox.deleteSync(recursive: true);
  });

  String stateOf(WebChatRig side, String name) =>
      side.store.transfers.lastWhere((t) => t.fileName == name).state.name;
  String idOf(String name) =>
      guest.store.transfers.lastWhere((t) => t.fileName == name).id;

  test('an offer the receiver accepted but queued behind its busy lanes is '
      'never cancelled as unanswered when the send budget fills', () async {
    final chunk = Uint8List(24 << 20);
    for (var i = 0; i < 4; i++) {
      await host.bridge.offerBytes(host.room!, '$i.bin', chunk);
    }
    await webPeerUntil(() => guest.store.transfers.length == 4);
    // 보내는 쪽 바이트가 멈춰 있어서 먼저 수락한 세 파일이 받는 쪽 자리를 계속 차지함
    host.connections.single.channel.buffer = 1 << 30;
    for (final name in ['0.bin', '1.bin', '2.bin']) {
      await guest.bridge.accept(idOf(name));
    }
    await webPeerUntil(
      () => [
        '0.bin',
        '1.bin',
        '2.bin',
      ].every((name) => stateOf(host, name) == TransferState.transferring.name),
    );
    await guest.bridge.accept(idOf('3.bin'));
    expect(stateOf(guest, '3.bin'), TransferState.accepted.name);
    await webPeerUntil(
      () => stateOf(host, '3.bin') == TransferState.accepted.name,
    );

    // 예산(RAM 원본 100 MiB)이 찬 상태에서 오래된 제안 정리가 돌아도 수락된 제안은 남음
    webChatStaleOfferAge = Duration.zero;
    await expectLater(
      host.bridge.offerBytes(host.room!, '4.bin', Uint8List(8 << 20)),
      throwsA(
        isA<WebPeerProblem>().having((e) => e.code, 'code', 'send-budget'),
      ),
    );
    await pumpEventQueue();
    expect(stateOf(host, '3.bin'), TransferState.accepted.name);
    expect(stateOf(guest, '3.bin'), TransferState.accepted.name);
  });

  test('a peer that answers every offer with a queue notice and accepts '
      'nothing cannot hold the send budget', () async {
    final chunk = Uint8List(24 << 20);
    for (var i = 0; i < 4; i++) {
      await host.bridge.offerBytes(host.room!, '$i.bin', chunk);
    }
    await webPeerUntil(() => guest.store.transfers.length == 4);
    for (var i = 0; i < 4; i++) {
      await guest.connections.single.channel.send(
        RTCDataChannelMessage(
          jsonEncode({'kind': 'file-queued', 'id': idOf('$i.bin')}),
        ),
      );
    }
    await pumpEventQueue();
    expect(
      {for (var i = 0; i < 4; i++) stateOf(host, '$i.bin')},
      {TransferState.offered.name},
    );

    // 예산이 차면 답 없는 오래된 제안을 취소하고 새 파일을 보낼 수 있음
    webChatStaleOfferAge = Duration.zero;
    await host.bridge.offerBytes(host.room!, '4.bin', Uint8List(8 << 20));
    await webPeerUntil(
      () => guest.store.transfers.any((t) => t.fileName == '4.bin'),
    );
    expect(stateOf(host, '4.bin'), TransferState.offered.name);
  });
}
