import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/store/in_memory_store.dart';
import '../web_peer_fake.dart';

class WebChatRig {
  WebChatRig._(
    this.identity,
    this.fingerprint,
    String? directory,
    Future<String?> Function(String)? chooseDirectory,
  ) {
    bridge = WebChatBridge(
      store: store,
      identity: identity,
      chooseDirectory: chooseDirectory ?? (_) async => directory,
    );
    bridge.sessionFactory =
        ({onState, onTextFrame, onControl, onTransfer, onError}) {
          final connection = WebPeerFakeConnection(fingerprint);
          connections.add(connection);
          final session = WebPeerSession(
            connectionFactory: (_) async => connection,
            onState: onState,
            onTextFrame: onTextFrame,
            onControl: onControl,
            onTransfer: onTransfer,
            onError: errors.add,
          );
          sessions.add(session);
          return session;
        };
  }
  final AppIdentity identity;
  final String fingerprint;
  final store = InMemoryStore();
  final connections = <WebPeerFakeConnection>[];
  final sessions = <WebPeerSession>[];
  final errors = <Object>[];
  late final WebChatBridge bridge;
  String? room;
  static Future<WebChatRig> create(
    String fingerprint, {
    String? directory,
    Future<String?> Function(String)? chooseDirectory,
  }) async => WebChatRig._(
    await AppIdentity.create(),
    fingerprint,
    directory,
    chooseDirectory,
  );

  Future<void> connect(WebChatRig guest) async {
    final offer = await bridge.createInvitation(conversationId: room);
    room = offer.conversationId;
    final answer = await guest.bridge.joinInvitation(offer.code);
    guest.room = answer.conversationId;
    final left = connections.last, right = guest.connections.last;
    left.channel.peer = right.channel;
    right.channel.peer = left.channel;
    right.onDataChannel!(right.channel);
    await bridge.acceptAnswer(room!, answer.code);
    left.channel.open();
    right.channel.open();
    await webPeerUntil(
      () =>
          store.conversation(room!)!.online &&
          guest.store.conversation(guest.room!)!.online &&
          guest.store.roomIntegrity.scope(guest.room!) != null,
    );
  }

  Future<void> dispose() async {
    await bridge.dispose();
    store.dispose();
  }
}
