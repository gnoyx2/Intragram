import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';
import 'package:stream_channel/stream_channel.dart';

import '../web_peer_fake.dart';
import 'handshake_pair.dart' show conv;

// 진짜 LinkRegistry 하나: v7 링크는 인메모리 채널, WebRTC는 가짜 연결 (자동 초대가 두 길을 다 씀)
class InviteSide {
  InviteSide._(this.identity, this.host, String fingerprint) {
    registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: identity,
    );
    registry.debugWebSessionFactory =
        ({onState, onTextFrame, onControl, onTransfer, onError}) {
          final connection = WebPeerFakeConnection(fingerprint);
          connections.add(connection);
          final session = WebPeerSession(
            connectionFactory: (_) async => connection,
            onState: onState,
            onTextFrame: onTextFrame,
            onControl: onControl,
            onTransfer: onTransfer,
            onError: onError,
          );
          sessions.add(session);
          return session;
        };
  }

  static Future<InviteSide> create(String host, String fingerprint) async {
    final side = InviteSide._(await AppIdentity.create(), host, fingerprint);
    addTearDown(side.dispose);
    return side;
  }

  final AppIdentity identity;
  final String host;
  final store = InMemoryStore();
  late final LinkRegistry registry;
  final connections = <WebPeerFakeConnection>[];
  final sessions = <WebPeerSession>[];

  PeerDevice get device => PeerDevice(
    peerId: identity.peerId,
    alias: identity.alias,
    platform: 'test',
    host: host,
    port: 7890,
    seenAt: DateTime(2026),
  );

  Iterable<Conversation> get webRooms =>
      store.conversations.where((c) => registry.isWebConversation(c.id));

  // 이 쪽이 other에게 v7 링크를 검. 양쪽 1:1 대화 id를 돌려줌
  Future<({String mine, String theirs})> dial(InviteSide other) async {
    final wire = StreamChannelController<dynamic>();
    final before = other.store.conversations.map((c) => c.id).toSet();
    await other.registry.acceptInbound(
      wire.foreign,
      remoteHost: host,
      remotePort: 7890,
    );
    final mine = await registry.debugAdoptDialledChannel(
      wire.local,
      remoteHost: other.host,
      remotePort: 7890,
    );
    await inviteUntil(
      () =>
          store.conversation(mine)?.secure == true &&
          other.store.conversations.any(
            (c) => !before.contains(c.id) && c.secure,
          ),
    );
    final theirs = other.store.conversations
        .firstWhere((c) => !before.contains(c.id))
        .id;
    return (mine: mine, theirs: theirs);
  }

  Future<void> dispose() async {
    await registry.disposeAll();
    store.dispose();
  }
}

// 자동 교환이 끝나 '이어지는 중'인 가짜 WebRTC 연결 한 쌍을 실제로 이음
Future<void> pairWebRtc(
  InviteSide host,
  int hostIndex,
  InviteSide member,
) async {
  await inviteUntil(
    () =>
        host.sessions.length > hostIndex &&
        host.sessions[hostIndex].state == 'connecting' &&
        member.sessions.isNotEmpty &&
        member.sessions.last.state == 'connecting',
  );
  final left = host.connections[hostIndex], right = member.connections.last;
  left.channel.peer = right.channel;
  right.channel.peer = left.channel;
  right.onDataChannel!(right.channel);
  left.channel.open();
  right.channel.open();
  await inviteUntil(
    () =>
        host.sessions[hostIndex].state == 'connected' &&
        member.sessions.last.state == 'connected',
  );
}

Future<void> inviteUntil(bool Function() check) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!check()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('auto invite');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

// 가짜 WebRTC 연결 한 쌍을 실제로 이음 (채널이 열리면 양쪽이 신원 증명을 주고받음)
void pairFakeWebRtc(
  WebPeerFakeConnection dialler,
  WebPeerFakeConnection answerer,
) {
  dialler.channel.peer = answerer.channel;
  answerer.channel.peer = dialler.channel;
  answerer.onDataChannel!(answerer.channel);
  dialler.channel.open();
  answerer.channel.open();
}

// 이 연결로 내보낸 제어 프레임 종류 (신원이 확인되기 전엔 신원 증명 말고는 아무것도 안 나가야 함)
Set<String> controlsSentOn(WebPeerFakeConnection connection) => {
  for (final message in connection.channel.sent)
    if (!message.isBinary)
      if (jsonDecode(message.text) case {
        'kind': 'control',
        'control': {'k': final String k},
      })
        k,
};

// 레지스트리 없이 손으로 프레임을 보내는 앱 링크: 규칙을 안 지키는 상대 역할
Future<({PeerLink link, AppIdentity identity})> rawInviteApp(
  InviteSide victim, {
  required bool victimDials,
}) async {
  final wire = StreamChannelController<dynamic>();
  final identity = await AppIdentity.create();
  final store = InMemoryStore()..upsertConversation(conv('raw', 'victim'));
  addTearDown(store.dispose);
  final link = PeerLink(
    conversationId: 'raw',
    channel: wire.local,
    store: store,
    identity: identity,
    crypto: await CryptoEngine().createSession(),
    dialledByUs: !victimDials,
  );
  addTearDown(link.close);
  if (victimDials) {
    await victim.registry.debugAdoptDialledChannel(
      wire.foreign,
      remoteHost: '192.168.1.30',
      remotePort: 7890,
    );
  } else {
    await victim.registry.acceptInbound(
      wire.foreign,
      remoteHost: '192.168.1.30',
      remotePort: 7890,
    );
  }
  await link.start();
  await inviteUntil(() => link.isSecure);
  return (link: link, identity: identity);
}

PeerDevice deviceOf(AppIdentity identity) => PeerDevice(
  peerId: identity.peerId,
  alias: 'raw',
  platform: 'test',
  host: '192.168.1.30',
  port: 7890,
  seenAt: DateTime(2026),
);
