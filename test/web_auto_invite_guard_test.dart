import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/network/web_peer.dart';

import 'support/web_chat_rig.dart';
import 'support/web_invite_rig.dart';

Matcher _problem(String code) =>
    throwsA(isA<WebPeerProblem>().having((p) => p.code, 'code', code));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    webInviteTimeout = const Duration(seconds: 20);
    webJoinDeadline = const Duration(seconds: 30);
  });

  test('the host of a v7 room refuses a WebRTC invite from a member it '
      'neither dialled nor verified, like a v7 room_join', () async {
    final host = await InviteSide.create('192.168.1.10', 'AA');
    final a = await InviteSide.create('192.168.1.11', 'BB');
    final b = await InviteSide.create('192.168.1.12', 'CC');
    final first = await a.dial(host);
    await b.dial(host);
    await host.registry.addPeersToRoom(first.theirs, [b.device]);
    final v7Room = host.registry.appRoomId!;
    await inviteUntil(() => host.store.conversation(v7Room)!.memberCount == 3);

    // 멤버 a가 자기 WebRTC 방으로 v7 호스트를 끌어들이려 함
    a.registry.debugDial = (_) => throw StateError('no dial in this test');
    final room = (await a.registry.createWebInvitation()).conversationId;
    await expectLater(
      a.registry.addPeersToRoom(room, [host.device]),
      _problem('auto-invite-refused'),
    );
    expect(host.webRooms, isEmpty);
  });

  test('the invited app cannot hand its seat to another device: an answer '
      'made by a different identity never enters the room', () async {
    final host = await InviteSide.create('192.168.1.10', 'AA');
    final other = await WebChatRig.create('CC');
    addTearDown(other.dispose);
    // 호스트에 직접 붙은 앱 B: 받은 초대 코드를 다른 기기 Y에 넘기고 Y의 응답을 돌려줌
    final raw = await rawInviteApp(host, victimDials: false);
    raw.link.onWebInvite = (id, code) => unawaited(() async {
      final joined = await other.bridge.joinInvitation(code);
      other.room = joined.conversationId;
      await raw.link.sendWebAnswer(id, joined.code);
    }());
    final room = (await host.registry.createWebInvitation()).conversationId;

    final adding = host.registry.addPeersToRoom(room, [deviceOf(raw.identity)]);
    await inviteUntil(
      () =>
          host.sessions.length > 1 &&
          host.sessions[1].state == 'connecting' &&
          other.sessions.isNotEmpty &&
          other.sessions.last.state == 'connecting',
    );
    pairFakeWebRtc(host.connections[1], other.connections.last);

    await expectLater(adding, _problem('auto-invite-failed'));
    expect(host.sessions[1].state, 'closed');
    expect(host.store.conversation(room)!.online, isFalse);
    expect(host.store.conversation(room)!.members, isEmpty);
    // Y는 방 프레임을 하나도 못 받음 (호스트가 신원을 확인하기 전엔 방 멤버가 아님)
    expect(controlsSentOn(host.connections[1]), {'identity'});
    // Y가 연결 직후 보낸 이름·기능 알림도 신원 확인 전이라 적용되지 않음
    expect(host.sessions[1].peerLanes, 1);
    expect(host.store.conversation(room)!.peerAlias, 'Web');
  });

  test('an app is not led to a third device: an invitation made by another '
      'identity than the inviting app is dropped', () async {
    webJoinDeadline = const Duration(milliseconds: 300);
    final victim = await InviteSide.create('192.168.1.20', 'BB');
    final third = await WebChatRig.create('CC');
    addTearDown(third.dispose);
    // 피해 앱이 직접 연결한 앱 M (그래서 M의 자동 초대는 받음): M이 제3 기기 T가 만든 초대 코드를 보냄
    final raw = await rawInviteApp(victim, victimDials: true);
    final offer = await third.bridge.createInvitation();
    third.room = offer.conversationId;
    final answered = Completer<void>();
    raw.link.onWebAnswer = (id, code) => unawaited(() async {
      if (code == null) return answered.completeError(StateError('refused'));
      await third.bridge.acceptAnswer(third.room!, code);
      answered.complete();
    }());
    await raw.link.sendWebInvite(newId(), offer.code);
    await answered.future;
    await inviteUntil(
      () =>
          victim.sessions.isNotEmpty &&
          victim.sessions.last.state == 'connecting',
    );
    pairFakeWebRtc(third.connections.last, victim.connections.last);

    // T의 신원 증명이 오면 초대한 앱이 아니라서 끊고, 빈 대화도 남기지 않음
    await inviteUntil(() => victim.sessions.last.state == 'closed');
    await inviteUntil(() => victim.webRooms.isEmpty);
    expect(controlsSentOn(victim.connections.last), {'identity'});
  });

  test('moving a chat whose app went offline reports that app as not '
      'invited', () async {
    final host = await InviteSide.create('192.168.1.10', 'AA');
    final app = await InviteSide.create('192.168.1.20', 'BB');
    final link = await app.dial(host);
    await app.registry.disconnect(link.mine);
    await inviteUntil(() => !host.store.conversation(link.theirs)!.online);
    final room = (await host.registry.createWebInvitation()).conversationId;

    expect(
      await host.registry.inviteConversationToWebRoom(link.theirs, room),
      1,
    );
  });
}
