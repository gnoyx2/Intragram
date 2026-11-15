import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/org_auth.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/network/web_peer_evidence.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'web_peer_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'blocked WebRTC identity cannot reconnect or inject pre-identity text',
    () async {
      final store = InMemoryStore();
      final registry = LinkRegistry(
        store: store,
        crypto: CryptoEngine(),
        identity: await AppIdentity.create(),
      );
      final identity = await AppIdentity.create();
      final sessions = <WebPeerSession>[];
      late WebPeerFakeConnection hostConnection;
      registry.debugWebSessionFactory =
          ({onState, onTextFrame, onControl, onTransfer, onError}) {
            hostConnection = WebPeerFakeConnection('AA');
            final session = WebPeerSession(
              connectionFactory: (_) async => hostConnection,
              onState: onState,
              onTextFrame: onTextFrame,
              onControl: onControl,
              onTransfer: onTransfer,
              onError: onError,
            );
            sessions.add(session);
            return session;
          };
      addTearDown(() async {
        await registry.disposeAll();
        for (final session in sessions) {
          await session.close();
        }
        store.dispose();
      });

      Future<({String room, WebPeerSession peer, WebPeerEvidence proof})>
      connect() async {
        final invitation = await registry.createWebInvitation();
        final connection = WebPeerFakeConnection('BB');
        final peer = WebPeerSession(connectionFactory: (_) async => connection);
        sessions.add(peer);
        final code = await peer.acceptOffer(invitation.code);
        hostConnection.channel.peer = connection.channel;
        connection.channel.peer = hostConnection.channel;
        connection.onDataChannel!(connection.channel);
        await registry.acceptWebAnswer(invitation.conversationId, code);
        hostConnection.channel.open();
        connection.channel.open();
        await webPeerUntil(() => peer.state == 'connected');
        return (
          room: invitation.conversationId,
          peer: peer,
          proof: WebPeerEvidence(
            identity: identity,
            sendControl: peer.sendControl,
          ),
        );
      }

      final first = await connect();
      await first.proof.start(first.peer.sessionBinding, dialled: false);
      await webPeerUntil(() => store.conversation(first.room)!.peerId != null);
      await registry.blockPeer(first.room);
      expect(registry.isBlocked(identity.peerId), isTrue);

      store.orgCredentials.activate(
        await issueDemoCredential(
          registry.identity,
          org: 'QA',
          dept: 'Test',
          role: 'Member',
        ),
      );
      final blocked = await connect();
      final messageId = 'd' * 32;
      await blocked.peer.sendText('blocked before identity', id: messageId);
      await blocked.proof.start(blocked.peer.sessionBinding, dialled: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(store.messageById(messageId), isNull);
      expect(store.conversation(blocked.room)!.online, isFalse);
      expect(
        hostConnection.channel.sent
            .where((data) => !data.isBinary)
            .map((data) => jsonDecode(data.text) as Map)
            .where(
              (frame) =>
                  frame['control']?['k'] == 'org-credential' &&
                  frame['control']?['credential'] != null,
            ),
        isEmpty,
        reason: 'blocked identities cannot receive our organization credential',
      );

      registry.unblockPeer(first.room);
      final allowed = await connect();
      await allowed.proof.start(allowed.peer.sessionBinding, dialled: false);
      await webPeerUntil(
        () => store.conversation(allowed.room)!.peerId != null,
      );
      await allowed.peer.sendText('unblocked', id: 'e' * 32);
      await webPeerUntil(() => store.messageById('e' * 32) != null);
      expect(store.conversation(allowed.room)!.online, isTrue);
    },
  );
}
