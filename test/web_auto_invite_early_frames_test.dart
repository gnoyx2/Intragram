import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/network/web_peer_protocol.dart' show webPeerNewId;
import 'package:intragram/store/models.dart';

import 'support/web_chat_rig.dart';
import 'support/web_invite_rig.dart';
import 'web_peer_fake.dart';

List<String> _texts(InviteSide side, String room) => [
  for (final m in side.store.messages(room))
    if (m.kind == MessageKind.text) m.text!,
];

// 채널이 열리자마자 넣는 원시 프레임: 신원 증명(서명이 끝나야 나감)보다 먼저 도착함
Future<void> _early(WebPeerFakeConnection from, Map<String, dynamic> frame) =>
    from.channel.send(RTCDataChannelMessage(jsonEncode(frame)));

// 자동 초대로 생긴 WebRTC 링크는 신원이 증명되기 전까지 방 밖임: 그 전에 온 프레임은 맞는 기기면 증명 뒤에
// 적용하고, 다른 기기거나 차단된 기기면 끝내 적용하지 않음
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    webInviteTimeout = const Duration(seconds: 20);
    webJoinDeadline = const Duration(seconds: 30);
  });

  test('text and a file offer sent before the identity proof are never '
      'applied when the device turns out to be someone else', () async {
    final host = await InviteSide.create('192.168.1.10', 'AA');
    final other = await WebChatRig.create('CC');
    addTearDown(other.dispose);
    // 호스트에 붙은 앱이 받은 초대 코드를 다른 기기 Y에 넘기고 Y의 응답을 돌려줌
    final raw = await rawInviteApp(host, victimDials: false);
    raw.link.onWebInvite = (id, code) => unawaited(() async {
      final joined = await other.bridge.joinInvitation(code);
      await raw.link.sendWebAnswer(id, joined.code);
    }());
    final room = (await host.registry.createWebInvitation()).conversationId;
    final adding = host.registry.addPeersToRoom(room, [deviceOf(raw.identity)]);
    final refused = expectLater(
      adding,
      throwsA(
        isA<WebPeerProblem>().having(
          (p) => p.code,
          'code',
          'auto-invite-failed',
        ),
      ),
    );
    await inviteUntil(
      () =>
          host.sessions.length > 1 &&
          host.sessions[1].state == 'connecting' &&
          other.sessions.isNotEmpty &&
          other.sessions.last.state == 'connecting',
    );
    pairFakeWebRtc(host.connections[1], other.connections.last);
    final y = other.connections.last;
    await _early(y, {
      'kind': 'text',
      'id': webPeerNewId(),
      'text': 'too early',
    });
    await _early(y, {
      'kind': 'file-offer',
      'id': webPeerNewId(),
      'name': 'early.bin',
      'size': 3,
    });

    await refused;
    expect(host.sessions[1].state, 'closed');
    expect(_texts(host, room), isEmpty);
    expect(host.store.transfers, isEmpty);
    expect(host.store.conversation(room)!.members, isEmpty);
    expect(controlsSentOn(host.connections[1]), {'identity'});
  });

  test('text sent before the identity proof by the invited app itself is '
      'applied once the proof arrives', () async {
    final host = await InviteSide.create('192.168.1.10', 'AA');
    final app = await InviteSide.create('192.168.1.20', 'BB');
    await app.dial(host);
    final room = (await host.registry.createWebInvitation()).conversationId;
    final adding = host.registry.addPeersToRoom(room, [app.device]);
    await inviteUntil(
      () =>
          host.sessions.length > 1 &&
          host.sessions[1].state == 'connecting' &&
          app.sessions.isNotEmpty &&
          app.sessions.last.state == 'connecting',
    );
    pairFakeWebRtc(host.connections[1], app.connections.last);
    await _early(app.connections.last, {
      'kind': 'text',
      'id': webPeerNewId(),
      'text': 'early but mine',
    });
    expect(_texts(host, room), isEmpty);

    await adding;
    await inviteUntil(() => _texts(host, room).contains('early but mine'));
    expect(host.store.conversation(room)!.peerId, app.identity.peerId);
  });

  test('blocking the app while its automatic invite is still connecting '
      'keeps it out of the room', () async {
    final host = await InviteSide.create('192.168.1.10', 'AA');
    final app = await InviteSide.create('192.168.1.20', 'BB');
    final link = await app.dial(host);
    final room = (await host.registry.createWebInvitation()).conversationId;
    final adding = host.registry.addPeersToRoom(room, [app.device]);
    final refused = expectLater(adding, throwsA(isA<WebPeerProblem>()));
    await inviteUntil(
      () =>
          host.sessions.length > 1 &&
          host.sessions[1].state == 'connecting' &&
          app.sessions.isNotEmpty &&
          app.sessions.last.state == 'connecting',
    );
    await host.registry.blockPeer(link.theirs);
    // 차단 뒤에도 아직 이어지는 중이면 끝까지 이어 봄: 신원 증명이 와도 방에 들이지 않아야 함
    if (host.sessions[1].state == 'connecting' &&
        app.sessions.last.state == 'connecting') {
      pairFakeWebRtc(host.connections[1], app.connections.last);
    }

    await refused;
    await inviteUntil(() => host.sessions[1].state == 'closed');
    expect(host.store.conversation(room)?.members ?? const {}, isEmpty);
    expect(host.store.conversation(room)?.online ?? false, isFalse);
    expect(
      controlsSentOn(host.connections[1]).difference({'identity'}),
      isEmpty,
    );
  });
}
