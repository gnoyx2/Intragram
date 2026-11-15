import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/network/protocol.dart' show InnerFrame;
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/network/web_peer_evidence.dart';
import 'package:intragram/store/models.dart';

import 'support/web_chat_rig.dart';
import 'web_peer_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reconnecting signed author cannot bypass integrity before identity proof',
    () async {
      final host = await WebChatRig.create('AA');
      final member = await WebChatRig.create('BB');
      final other = await WebChatRig.create('DD');
      final newcomerConnection = WebPeerFakeConnection('CC');
      final newcomer = WebPeerSession(
        connectionFactory: (_) async => newcomerConnection,
      );
      addTearDown(() async {
        await newcomer.close();
        await member.dispose();
        await other.dispose();
        await host.dispose();
      });
      await host.connect(member);
      await host.connect(other);
      await member.bridge.sendText(member.room!, 'signed before reconnect');
      await webPeerUntil(
        () => host.store
            .messages(host.room!)
            .any((message) => message.text == 'signed before reconnect'),
      );
      final offer = await host.bridge.createInvitation(
        conversationId: host.room,
      );
      final answer = await newcomer.acceptOffer(offer.code);
      final hostConnection = host.connections.last;
      hostConnection.channel.peer = newcomerConnection.channel;
      newcomerConnection.channel.peer = hostConnection.channel;
      newcomerConnection.onDataChannel!(newcomerConnection.channel);
      await host.bridge.acceptAnswer(host.room!, answer);
      hostConnection.channel.open();
      newcomerConnection.channel.open();
      await webPeerUntil(() => newcomer.state == 'connected');
      expect(host.store.conversation(host.room!)!.isRoom, isTrue);
      expect(host.store.roomIntegrity.scope(host.room!), isNotNull);
      final id = 'f' * 32;
      await newcomer.sendText('unsigned before identity', id: id);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        host.store.messageById(id),
        isNull,
        reason: 'unknown authors cannot bypass signed room validation',
      );
      expect(member.store.messageById(id), isNull);
      final proof = WebPeerEvidence(
        identity: member.identity,
        sendControl: newcomer.sendControl,
      );
      addTearDown(proof.clear);
      await proof.start(newcomer.sessionBinding, dialled: false);
      await webPeerUntil(
        () =>
            host
                .bridge
                .rooms[host.room!]!
                .peers
                .values
                .last
                .proof
                .peerIdentity !=
            null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        host.store.messageById(id),
        isNull,
        reason: 'identity verification must not approve an unsigned backlog',
      );
      expect(member.store.messageById(id), isNull);
    },
  );

  // 신원 증명 전에 보류 클로저(개수 32개 미만)에 대용량 프레임을 연속으로 쌓아 메모리를 붙잡지 못하게 총 바이트 상한(8 MiB)으로 끊음
  test(
    'deferred frames before identity proof are capped by total byte size',
    () async {
      final host = await WebChatRig.create('AA');
      final member = await WebChatRig.create('BB');
      final other = await WebChatRig.create('DD');
      final newcomerConnection = WebPeerFakeConnection('CC');
      final newcomer = WebPeerSession(
        connectionFactory: (_) async => newcomerConnection,
      );
      addTearDown(() async {
        await newcomer.close();
        await member.dispose();
        await other.dispose();
        await host.dispose();
      });
      host.store.largeMessageMode = LargeMessageMode.unlimited;
      await host.connect(member);
      await host.connect(other);

      final offer = await host.bridge.createInvitation(
        conversationId: host.room,
      );
      final answer = await newcomer.acceptOffer(offer.code);
      final hostConnection = host.connections.last;
      hostConnection.channel.peer = newcomerConnection.channel;
      newcomerConnection.channel.peer = hostConnection.channel;
      newcomerConnection.onDataChannel!(newcomerConnection.channel);
      await host.bridge.acceptAnswer(host.room!, answer);
      hostConnection.channel.open();
      newcomerConnection.channel.open();
      await webPeerUntil(() => newcomer.state == 'connected');

      final hostPeer = host.bridge.rooms[host.room!]!.peers.values.last;
      final threeMiB = 'x' * (3 * 1024 * 1024);
      await newcomer.sendText(
        threeMiB,
        id: '1' * 32,
        maxBytes: kFrameCeilingBytes,
      );
      final signedFrame = await host.store.roomIntegrity.sign(
        host.room!,
        member.identity,
        InnerFrame.message(
          id: '2' * 32,
          text: threeMiB,
          ttlSeconds: 0,
          timestampMs: 1,
        ),
      );
      await newcomer.sendControl({
        'k': 'native-room',
        'host': host.identity.peerId,
        'origin': 'c' * 32,
        'alias': 'Newcomer',
        'frame': signedFrame,
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(hostPeer.pendingIdentity, hasLength(1));
      expect(hostPeer.pendingNative, hasLength(1));
      expect(hostPeer.pendingIdentityBytes, greaterThan(6 * 1024 * 1024));
      expect(hostPeer.session.state, 'connected');

      // 세 번째 3 MiB 프레임(누적 9 MiB > webChatMaxPendingIdentityBytes)이 들어오면 보류 목록을 비우고 세션을 닫음
      await newcomer.sendText(
        threeMiB,
        id: '3' * 32,
        maxBytes: kFrameCeilingBytes,
      );
      await webPeerUntil(() => hostPeer.session.state == 'closed');
      expect(hostPeer.pendingIdentity, isEmpty);
      expect(hostPeer.pendingNative, isEmpty);
      expect(hostPeer.pendingIdentityBytes, 0);
    },
  );
}
