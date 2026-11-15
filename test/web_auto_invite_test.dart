import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';
import 'package:stream_channel/stream_channel.dart';

import 'support/handshake_pair.dart' show conv;
import 'support/web_chat_rig.dart';
import 'support/web_invite_rig.dart';

Matcher _problem(String code) =>
    throwsA(isA<WebPeerProblem>().having((p) => p.code, 'code', code));

List<String> _texts(InviteSide side, String room) => [
  for (final m in side.store.messages(room))
    if (m.kind == MessageKind.text) m.text!,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    webInviteTimeout = const Duration(seconds: 20);
    webJoinDeadline = const Duration(seconds: 30);
    webInviteCooldown = const Duration(seconds: 60);
  });

  test('a nearby app that dialled the host joins the web room by itself: no '
      'v7 room appears and text flows over WebRTC', () async {
    final host = await InviteSide.create('192.168.1.10', 'AA');
    final app = await InviteSide.create('192.168.1.20', 'BB');
    await app.dial(host);
    final room = (await host.registry.createWebInvitation()).conversationId;
    expect(host.registry.hostsWebRoom(room), isTrue);

    final adding = host.registry.addPeersToRoom(room, [app.device]);
    await pairWebRtc(host, 1, app);
    await adding;

    expect(host.registry.appRoomId, isNull);
    final joined = app.webRooms.single;
    expect(app.registry.hostsWebRoom(joined.id), isFalse);
    await inviteUntil(() => host.store.conversation(room)!.online);
    await host.registry.sendText(room, 'over webrtc');
    await inviteUntil(() => _texts(app, joined.id).contains('over webrtc'));
    await app.registry.sendText(joined.id, 'back');
    await inviteUntil(() => _texts(host, room).contains('back'));
    // 앱이 알린 기기 종류가 보임 (브라우저로 표시하지 않음)
    await inviteUntil(
      () =>
          app.store.conversation(joined.id)!.peerPlatform ==
              host.identity.platform &&
          host.store.conversation(room)!.peerPlatform == app.identity.platform,
    );
    expect(host.identity.platform, isNot('Browser'));
    // 같은 앱을 다시 골라도 연결을 또 만들지 않음
    await inviteUntil(
      () => host.store.conversation(room)!.peerId == app.identity.peerId,
    );
    final sessions = host.sessions.length;
    await host.registry.addPeersToRoom(room, [app.device]);
    expect(host.sessions.length, sessions);
  });

  test('an app the host dialled refuses until both confirmed the security '
      'code, like a v7 room invite', () async {
    final host = await InviteSide.create('192.168.1.10', 'AA');
    final app = await InviteSide.create('192.168.1.20', 'BB');
    final link = await host.dial(app);
    final room = (await host.registry.createWebInvitation()).conversationId;

    await expectLater(
      host.registry.addPeersToRoom(room, [app.device]),
      _problem('auto-invite-refused'),
    );
    expect(app.webRooms, isEmpty);
    expect(host.sessions.last.state, 'closed');

    final sas = host.store.conversation(link.mine)!.sas;
    host.registry.markVerified(link.mine, expectedSas: sas);
    app.registry.markVerified(link.theirs, expectedSas: sas);
    await inviteUntil(
      () =>
          host.store.conversation(link.mine)!.verified &&
          app.store.conversation(link.theirs)!.verified,
    );
    final adding = host.registry.addPeersToRoom(room, [app.device]);
    await pairWebRtc(host, 2, app);
    await adding;
    expect(app.webRooms, hasLength(1));
    // 새 WebRTC 링크의 보안 코드는 따로 확인함 (v7 확인을 이어받지 않음)
    expect(app.webRooms.single.verified, isFalse);
  });

  test('one link keeps a single live auto-joined room and an unopened one is '
      'dropped', () async {
    webJoinDeadline = const Duration(milliseconds: 150);
    webInviteCooldown = const Duration(milliseconds: 300);
    final host = await InviteSide.create('192.168.1.10', 'AA');
    final app = await InviteSide.create('192.168.1.20', 'BB');
    await app.dial(host);
    final first = (await host.registry.createWebInvitation()).conversationId;
    final second = (await host.registry.createWebInvitation()).conversationId;

    final adding = host.registry.addPeersToRoom(first, [app.device]);
    await inviteUntil(() => app.webRooms.isNotEmpty);
    await expectLater(
      host.registry.addPeersToRoom(second, [app.device]),
      _problem('auto-invite-refused'),
    );
    // 호스트 쪽 연결이 끝내 안 열림: 호스트는 실패로 알고, 앱은 빈 대화를 남기지 않음
    await expectLater(adding, _problem('auto-invite-failed'));
    await inviteUntil(() => app.webRooms.isEmpty);
    // 실패한 뒤 한동안은 같은 링크의 새 초대를 거절하고, 그 뒤엔 다시 받음
    webJoinDeadline = const Duration(seconds: 30);
    await expectLater(
      host.registry.addPeersToRoom(second, [app.device]),
      _problem('auto-invite-refused'),
    );
    await Future<void>.delayed(webInviteCooldown);
    final index = host.sessions.length;
    final again = host.registry.addPeersToRoom(second, [app.device]);
    await pairWebRtc(host, index, app);
    await again;
    expect(app.webRooms, hasLength(1));
  });

  test('an app that never answers (older version) times out and leaves no '
      'pending peer', () async {
    webInviteTimeout = const Duration(milliseconds: 150);
    final host = await InviteSide.create('192.168.1.10', 'AA');
    // 초대 프레임을 모르는 옛 앱처럼 아무 응답도 하지 않는 링크
    final wire = StreamChannelController<dynamic>();
    await host.registry.acceptInbound(
      wire.foreign,
      remoteHost: '192.168.1.30',
      remotePort: 7890,
    );
    final identity = await AppIdentity.create();
    final store = InMemoryStore()..upsertConversation(conv('old', 'host'));
    addTearDown(store.dispose);
    final old = PeerLink(
      conversationId: 'old',
      channel: wire.local,
      store: store,
      identity: identity,
      crypto: await CryptoEngine().createSession(),
      dialledByUs: true,
    )..onWebInvite = (_, _) {};
    await old.start();
    await inviteUntil(() => old.isSecure);
    final room = (await host.registry.createWebInvitation()).conversationId;

    await expectLater(
      host.registry.addPeersToRoom(room, [
        PeerDevice(
          peerId: identity.peerId,
          alias: 'old',
          platform: 'test',
          host: '192.168.1.30',
          port: 7890,
          seenAt: DateTime(2026),
        ),
      ]),
      _problem('auto-invite-failed'),
    );
    expect(host.sessions.last.state, 'closed');
    await old.close();
  });

  test('a hand-typed answer never lands on an automatic invitation and '
      'cancelling the dialog leaves it alone', () async {
    final host = await WebChatRig.create('AA');
    final guest = await WebChatRig.create('BB');
    addTearDown(host.dispose);
    addTearDown(guest.dispose);
    final manual = await host.bridge.createInvitation();
    final room = manual.conversationId;
    final held = Completer<String>();
    final automatic = host.bridge.inviteThrough(
      room,
      guest.identity.peerId,
      (_) => held.future,
      const Duration(seconds: 5),
    );
    await pumpEventQueue();
    expect(host.sessions[1].state, 'waiting');

    final answer = await guest.bridge.joinInvitation(manual.code);
    await host.bridge.acceptAnswer(room, answer.code);
    expect(host.sessions[0].state, 'connecting');
    expect(host.sessions[1].state, 'waiting');
    await host.bridge.cancelInvitation(room);
    expect(host.sessions[0].state, 'closed');
    expect(host.sessions[1].state, 'waiting');

    held.completeError(const WebPeerProblem('auto-invite-refused'));
    await expectLater(automatic, _problem('auto-invite-refused'));
    expect(host.sessions[1].state, 'closed');
  });

  test('a v7 room moves to a web room: every member is invited and the host '
      'relays between them', () async {
    final host = await InviteSide.create('192.168.1.10', 'AA');
    final a = await InviteSide.create('192.168.1.11', 'BB');
    final b = await InviteSide.create('192.168.1.12', 'CC');
    final first = await a.dial(host);
    await b.dial(host);
    await host.registry.addPeersToRoom(first.theirs, [b.device]);
    final v7Room = host.registry.appRoomId!;
    await inviteUntil(() => host.store.conversation(v7Room)!.memberCount == 3);

    final room = (await host.registry.createWebInvitation()).conversationId;
    final moving = host.registry.inviteConversationToWebRoom(v7Room, room);
    await pairWebRtc(host, 1, a);
    await pairWebRtc(host, 2, b);
    expect(await moving, 0);

    final roomA = a.webRooms.single.id, roomB = b.webRooms.single.id;
    await inviteUntil(() => b.store.conversation(roomB)!.isRoom);
    await a.registry.sendText(roomA, 'from a');
    await inviteUntil(() => _texts(b, roomB).contains('from a'));
    expect(_texts(host, room), contains('from a'));
    // 예전 v7 방과 기록은 그대로 남음
    expect(host.registry.appRoomId, v7Room);
    expect(host.store.conversation(v7Room)!.online, isTrue);
  });
}
