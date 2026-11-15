import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/web_chat_bridge.dart';

import 'support/web_chat_rig.dart';
import 'support/web_invite_rig.dart';

// 자동 초대가 방을 못 연 채 끝나면 같은 링크는 한동안 새 자동 초대를 받지 않음: 초대만 되풀이해서
// WebRTC 연결 시도를 계속 일으킬 수 없음. 초대한 쪽에는 평소와 같은 거절(코드 없는 응답)이 감
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    webJoinDeadline = const Duration(seconds: 30);
    webInviteCooldown = const Duration(seconds: 60);
  });

  const wait = Duration(milliseconds: 300);
  Future<void> afterWait() =>
      Future<void>.delayed(wait + const Duration(milliseconds: 100));

  // 초대를 보내고 받은 응답 코드를 돌려줌 (거절이면 null)
  Future<String?> invite(PeerLink link, String code) async {
    final id = newId();
    final answered = Completer<String?>();
    link.onWebAnswer = (answerId, answer) {
      if (answerId == id && !answered.isCompleted) answered.complete(answer);
    };
    await link.sendWebInvite(id, code);
    return answered.future.timeout(const Duration(seconds: 5));
  }

  // 피해 앱이 직접 연결한 앱(그래서 그 앱의 자동 초대를 받음)과, 초대 코드를 만들어 줄 다른 기기
  Future<({InviteSide victim, PeerLink link, WebChatRig other})> rig() async {
    final victim = await InviteSide.create('192.168.1.20', 'BB');
    final other = await WebChatRig.create('CC');
    addTearDown(other.dispose);
    final raw = await rawInviteApp(victim, victimDials: true);
    return (victim: victim, link: raw.link, other: other);
  }

  test('an invitation that cannot be joined makes the link refuse new ones '
      'until the wait is over', () async {
    webInviteCooldown = wait;
    final r = await rig();

    expect(await invite(r.link, 'IGW1.not-an-invitation'), isNull);
    final attempts = r.victim.connections.length;
    final offer = await r.other.bridge.createInvitation();
    expect(await invite(r.link, offer.code), isNull);
    // 기다리는 동안엔 WebRTC 연결을 만들지도 않음
    expect(r.victim.connections.length, attempts);
    expect(r.victim.webRooms, isEmpty);

    await afterWait();
    expect(await invite(r.link, offer.code), isNotNull);
    expect(r.victim.connections.length, attempts + 1);
  });

  test('a room that never opens before the deadline starts the wait', () async {
    webJoinDeadline = const Duration(milliseconds: 150);
    webInviteCooldown = wait;
    final r = await rig();

    final first = await r.other.bridge.createInvitation();
    expect(await invite(r.link, first.code), isNotNull);
    await inviteUntil(() => r.victim.webRooms.isEmpty);
    final attempts = r.victim.connections.length;
    final second = await r.other.bridge.createInvitation();
    expect(await invite(r.link, second.code), isNull);
    expect(r.victim.connections.length, attempts);

    await afterWait();
    expect(await invite(r.link, second.code), isNotNull);
  });

  test('a link that closed before it opened counts as failed right away, '
      'without waiting for the deadline', () async {
    webInviteCooldown = wait;
    final r = await rig();

    // 다른 기기가 만든 초대라 연결된 뒤 신원이 안 맞아 끊김 (기한 30초는 한참 남음)
    final first = await r.other.bridge.createInvitation();
    final answer = await invite(r.link, first.code);
    await r.other.bridge.acceptAnswer(first.conversationId, answer!);
    await inviteUntil(() => r.victim.sessions.last.state == 'connecting');
    pairFakeWebRtc(r.other.connections.last, r.victim.connections.last);
    await inviteUntil(() => r.victim.sessions.last.state == 'closed');

    final attempts = r.victim.connections.length;
    final second = await r.other.bridge.createInvitation();
    expect(await invite(r.link, second.code), isNull);
    expect(r.victim.connections.length, attempts);
    // 죽은 방의 빈 대화도 기한을 안 기다리고 치움
    expect(r.victim.webRooms, isEmpty);

    await afterWait();
    expect(await invite(r.link, second.code), isNotNull);
  });

  test('a room that opened and then ended does not start the wait', () async {
    final host = await InviteSide.create('192.168.1.10', 'AA');
    final app = await InviteSide.create('192.168.1.20', 'BB');
    await app.dial(host);
    final first = (await host.registry.createWebInvitation()).conversationId;
    final adding = host.registry.addPeersToRoom(first, [app.device]);
    await pairWebRtc(host, 1, app);
    await adding;
    await host.registry.disconnect(first);
    // 가짜 연결은 닫힘을 상대에게 안 알려서 앱 쪽 채널을 직접 닫음
    await app.connections.last.channel.close();
    await inviteUntil(() => !app.webRooms.single.online);

    final second = (await host.registry.createWebInvitation()).conversationId;
    final index = host.sessions.length;
    final again = host.registry.addPeersToRoom(second, [app.device]);
    await pairWebRtc(host, index, app);
    await again;
    expect(app.webRooms.where((c) => c.online), hasLength(1));
  });
}
