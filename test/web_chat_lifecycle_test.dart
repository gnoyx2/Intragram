import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/secure_web_ui_peer.dart';
import 'support/web_chat_rig.dart';
import 'web_peer_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InMemoryStore store;
  late WebChatBridge bridge;
  late List<SecureWebUiPeer> peers;
  late Directory directory;
  Future<String?> Function(String)? chooseDirectory;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('web-chat-lifecycle-');
    store = InMemoryStore();
    peers = [];
    chooseDirectory = null;
    bridge = WebChatBridge(
      store: store,
      identity: await AppIdentity.create(),
      chooseDirectory: (name) async =>
          await chooseDirectory?.call(name) ?? directory.path,
    );
    bridge.sessionFactory =
        ({onState, onTextFrame, onControl, onTransfer, onError}) {
          final peer = SecureWebUiPeer(
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
    await bridge.dispose();
    store.dispose();
    directory.deleteSync(recursive: true);
  });

  test(
    'closed peer cannot mutate a reopened room through late callbacks',
    () async {
      final invitation = await bridge.createInvitation();
      final id = invitation.conversationId;
      final old = peers.single;
      old.connect();
      await bridge.closeRoom(id);
      await bridge.createInvitation(conversationId: id);
      peers.last.connect();
      old.text('a' * 32, 'Late text');
      old.file('b' * 32, 10);
      old.control({'k': 'rename', 'alias': 'Stale alias'});
      old.onError?.call(StateError('Late error'));
      old.onState?.call('connected');
      expect(store.messageById('a' * 32), isNull);
      expect(store.transfer('b' * 32), isNull);
      expect(store.conversation(id)!.peerAlias, isNot('Stale alias'));
      expect(store.conversation(id)!.online, isTrue);
    },
  );

  test('file consent selected before close cannot save after reopen', () async {
    final invitation = await bridge.createInvitation();
    final id = invitation.conversationId;
    peers.single.connect();
    final selected = Completer<String?>(), selecting = Completer<void>();
    chooseDirectory = (_) {
      selecting.complete();
      return selected.future;
    };
    final bytes = Uint8List.fromList([1, 2, 3]);
    peers.single.file('c' * 32, bytes.length);
    await bridge.accept('c' * 32);
    peers.single.file('c' * 32, bytes.length, state: 'complete', bytes: bytes);
    await selecting.future;
    await bridge.closeRoom(id);
    await bridge.createInvitation(conversationId: id);
    peers.last.connect();
    selected.complete(directory.path);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(directory.listSync(), isEmpty);
    expect(store.transfer('c' * 32)!.state, TransferState.failed);
  });

  test(
    'close clears transient send snapshots before asynchronous teardown',
    () async {
      final host = await WebChatRig.create('AA'),
          guest = await WebChatRig.create('BB');
      addTearDown(host.dispose);
      addTearDown(guest.dispose);
      await host.connect(guest);
      await host.bridge.offerBytes(
        host.room!,
        'private.bin',
        Uint8List.fromList([1, 2, 3]),
      );
      final snapshot =
          host.bridge.rooms[host.room!]!.outgoing.values.single.bytes;
      expect(snapshot, [1, 2, 3]);
      final closing = host.bridge.closeRoom(host.room!);
      expect(snapshot, [0, 0, 0]);
      expect(host.store.conversation(host.room!)!.online, isFalse);
      await closing;
    },
  );

  test(
    'dispose finishes observable store updates before its first await',
    () async {
      final invitation = await bridge.createInvitation();
      peers.single.connect();
      final closing = bridge.dispose();
      expect(store.conversation(invitation.conversationId)!.online, isFalse);
      expect(store.conversation(invitation.conversationId)!.verified, isFalse);
      await closing;
    },
  );

  test(
    'burned text stays retired after the transport replay window advances',
    () async {
      final host = await WebChatRig.create('AA'),
          guest = await WebChatRig.create('BB');
      addTearDown(host.dispose);
      addTearDown(guest.dispose);
      await host.connect(guest);
      await guest.bridge.sendText(guest.room!, 'original');
      await webPeerUntil(() => host.store.messages(host.room!).isNotEmpty);
      final id = host.store.messages(host.room!).single.id;
      await guest.sessions.single.sendControl({'k': 'burn', 'id': id});
      await webPeerUntil(() => host.store.messageById(id) == null);
      for (var i = 0; i < 1005; i++) {
        await guest.sessions.single.sendControl({'k': 'typing', 'on': false});
      }
      await guest.sessions.single.sendText('replayed after burn', id: id);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(host.store.messageById(id), isNull);
    },
  );
}
