import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/network/web_peer_evidence.dart';

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
}
