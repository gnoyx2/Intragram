import 'package:flutter_test/flutter_test.dart';

import 'support/web_invite_rig.dart';

// 차단은 사람(신원) 단위: v7 대화와 따로 열린 WebRTC 대화 어느 쪽에서 차단해도 그 사람과의 링크가 전부 끊김
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({InviteSide host, InviteSide app, String v7, String room})>
  joined() async {
    final host = await InviteSide.create('192.168.1.10', 'AA');
    final app = await InviteSide.create('192.168.1.20', 'BB');
    final link = await app.dial(host);
    final room = (await host.registry.createWebInvitation()).conversationId;
    final adding = host.registry.addPeersToRoom(room, [app.device]);
    await pairWebRtc(host, 1, app);
    await adding;
    await inviteUntil(
      () => host.store.conversation(room)!.peerId == app.identity.peerId,
    );
    return (host: host, app: app, v7: link.theirs, room: room);
  }

  test('blocking the v7 chat also closes the WebRTC room that person was '
      'auto-invited into', () async {
    final r = await joined();

    await r.host.registry.blockPeer(r.v7);

    await inviteUntil(() => r.host.sessions[1].state == 'closed');
    await inviteUntil(() => !r.host.store.conversation(r.room)!.online);
    expect(r.host.store.conversation(r.room)!.blocked, isTrue);
    expect(r.host.store.conversation(r.v7)!.blocked, isTrue);

    // 풀면 그 사람의 대화가 모두 풀림
    r.host.registry.unblockPeer(r.v7);
    expect(r.host.store.conversation(r.room)!.blocked, isFalse);
    expect(r.host.store.conversation(r.v7)!.blocked, isFalse);
  });

  test('blocking the WebRTC chat also closes the v7 link with the same '
      'person', () async {
    final r = await joined();

    await r.host.registry.blockPeer(r.room);

    await inviteUntil(() => !r.host.store.conversation(r.v7)!.online);
    expect(r.host.store.conversation(r.v7)!.blocked, isTrue);
    expect(r.host.store.conversation(r.room)!.blocked, isTrue);
    expect(r.host.sessions[1].state, 'closed');

    r.host.registry.unblockPeer(r.room);
    expect(r.host.store.conversation(r.v7)!.blocked, isFalse);
  });
}
