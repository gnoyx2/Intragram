import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';
import 'support/secure_web_ui_peer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InMemoryStore store;
  late LinkRegistry registry;
  late Directory dir;
  late List<_Peer> peers;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('web_chat_bridge');
    store = InMemoryStore();
    peers = [];
    registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: await AppIdentity.create(),
      chooseDirectory: (_) async => dir.path,
    );
    registry.debugWebSessionFactory =
        ({onState, onTextFrame, onControl, onTransfer, onError}) {
          final peer = _Peer(
            onState: onState,
            onTextFrame: onTextFrame,
            onControl: onControl,
            onTransfer: onTransfer,
            onError: onError,
          );
          peers.add(peer);
          return peer;
        };
  });
  tearDown(() async {
    await registry.disposeAll();
    store.dispose();
    dir.deleteSync(recursive: true);
  });
  Future<void> until(bool Function() check) async {
    final end = DateTime.now().add(const Duration(seconds: 3));
    while (!check()) {
      if (DateTime.now().isAfter(end)) throw TimeoutException('bridge');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test(
    'shared native store receives text, metadata, receipts, reactions and verification',
    () async {
      final invitation = await registry.createWebInvitation();
      final id = invitation.conversationId;
      expect(registry.isWebConversation(id), isTrue);
      peers.first.connect();
      expect(store.conversation(id)!.secure, isTrue);
      peers.first.text('a' * 32, 'Incoming 한글');
      peers.first.control({'k': 'meta', 'id': 'a' * 32, 'ttl': 5});
      await registry.markRoomRead(id);
      expect(store.messageById('a' * 32)!.delivery, DeliveryState.read);
      expect(store.messageById('a' * 32)!.ttlSeconds, 5);
      expect(store.messageById('a' * 32)!.burnAt, isNotNull);
      await registry.sendText(id, 'Shared composer', replyToId: 'a' * 32);
      final sent = store.messages(id).last;
      expect(sent.replyToId, 'a' * 32);
      expect(peers.first.texts, ['Shared composer']);
      peers.first.control({'k': 'receipt', 'id': sent.id});
      peers.first.control({'k': 'read', 'id': sent.id});
      expect(store.messageById(sent.id)!.delivery, DeliveryState.read);
      registry.toggleReaction(id, 'a' * 32, '👍');
      expect(peers.first.controls.any((c) => c['k'] == 'react'), isTrue);
      registry.markVerified(id, expectedSas: '123456');
      peers.first.control({'k': 'verify', 'sas': '123456'});
      expect(store.conversation(id)!.verified, isTrue);
      // 앱이 먼저 확인한 경우: 브라우저 확인이 '상대 확인 기다리는 중' 줄을 '서로 확인함'으로 닫아야 함
      expect(
        store
            .messages(id)
            .where(
              (m) => m.systemEvent?.kind == SystemEventKind.mutuallyVerified,
            ),
        hasLength(1),
      );
      registry.deleteMessageForEveryone(sent.id);
      await until(
        () => peers.first.controls.any(
          (c) => c['k'] == 'burn' && c['id'] == sent.id,
        ),
      );
      expect(store.messageById(sent.id), isNull);
    },
  );

  test(
    'host room preserves history, routes origins and rejects another member burn',
    () async {
      final first = await registry.createWebInvitation();
      peers.first.connect();
      peers.first.text('b' * 32, 'First member');
      await registry.createWebInvitation(conversationId: first.conversationId);
      peers.last.connect();
      expect(store.conversation(first.conversationId)!.isRoom, isTrue);
      peers.first.text('c' * 32, 'Relayed');
      final relay = peers.last.controls.lastWhere((c) => c['k'] == 'room-msg');
      expect(relay['text'], 'Relayed');
      peers.last.control({'k': 'burn', 'id': 'c' * 32});
      expect(store.messageById('c' * 32)!.burned, isFalse);
      peers.first.control({'k': 'burn', 'id': 'c' * 32});
      expect(store.messageById('c' * 32), isNull);
      expect(store.messageById('b' * 32)!.text, 'First member');
      await registry.cancelWebInvitation(first.conversationId);
      expect(peers.first.closeCount, 0);
      expect(peers.last.closeCount, 0);
    },
  );

  test(
    'file consent writes exact native bytes and shared tile metadata',
    () async {
      final invitation = await registry.createWebInvitation();
      peers.first.connect();
      final bytes = Uint8List.fromList(List.generate(300037, (i) => i % 251));
      peers.first.file('d' * 32, bytes.length);
      expect(store.transfer('d' * 32)!.state, TransferState.offered);
      await registry.acceptTransfer('d' * 32);
      expect(peers.first.accepted, ['d' * 32]);
      peers.first.file('d' * 32, bytes.length, state: 'complete', bytes: bytes);
      await until(
        () => store.transfer('d' * 32)!.state == TransferState.complete,
      );
      final file = store.transfer('d' * 32)!;
      expect(file.encrypted, isTrue);
      expect(file.conversationId, invitation.conversationId);
      expect(await File(file.localPath!).readAsBytes(), bytes);
      expect(store.messageById(file.id)!.kind, MessageKind.file);
      await registry.disconnect(invitation.conversationId);
      expect(store.conversation(invitation.conversationId)!.online, isFalse);
    },
  );

  test('concurrent consent reserves the global receive budget', () async {
    final room = await registry.createWebInvitation();
    peers.first.connect();
    await registry.createWebInvitation(conversationId: room.conversationId);
    peers.last.connect();
    peers.first.file('e' * 32, 60 * 1024 * 1024);
    peers.last.file('f' * 32, 60 * 1024 * 1024);
    await registry.acceptTransfer('e' * 32);
    await expectLater(
      registry.acceptTransfer('f' * 32),
      throwsA(isA<WebPeerProblem>()),
    );
    expect(peers.last.accepted, isEmpty);
  });

  test(
    'failed new invitation removes its pending conversation and peer',
    () async {
      registry.debugWebSessionFactory =
          ({onState, onTextFrame, onControl, onTransfer, onError}) =>
              _FailingPeer(onState: onState);
      await expectLater(registry.createWebInvitation(), throwsStateError);
      expect(store.conversations, isEmpty);
    },
  );
}

class _Peer extends SecureWebUiPeer {
  _Peer({
    super.onState,
    super.onTextFrame,
    super.onControl,
    super.onTransfer,
    super.onError,
  });
  @override
  Future<void> cancelFile(String id) async {}
  @override
  Future<void> rejectFile(String id) async {}
}

class _FailingPeer extends _Peer {
  _FailingPeer({super.onState});
  @override
  Future<String> createOffer() async => throw StateError('ICE unavailable');
}
