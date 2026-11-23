import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/test_identities.dart';

// 진짜 레지스트리 둘(호스트 a, 멤버 b)을 이음: 호스트가 다이얼하면 멤버가 인바운드로 받음
class _Pair {
  _Pair._(this.hostStore, this.host, this.memberStore, this.member);

  final InMemoryStore hostStore;
  final LinkRegistry host;
  final InMemoryStore memberStore;
  final LinkRegistry member;
  int dials = 0;

  static Future<_Pair> create() async {
    final hostStore = InMemoryStore();
    final memberStore = InMemoryStore();
    final host = LinkRegistry(
      store: hostStore,
      crypto: CryptoEngine(),
      identity: testIdentity('a', alias: 'host', platform: 'test'),
    );
    final member = LinkRegistry(
      store: memberStore,
      crypto: CryptoEngine(),
      identity: testIdentity('b', alias: 'member', platform: 'test'),
    );
    final pair = _Pair._(hostStore, host, memberStore, member);
    host.debugDial = (_) async {
      pair.dials++;
      final wire = StreamChannelController<dynamic>();
      await member.acceptInbound(wire.foreign, remoteHost: '192.168.1.1');
      return wire.local;
    };
    addTearDown(() async {
      await host.disposeAll();
      await member.disposeAll();
      hostStore.dispose();
      memberStore.dispose();
    });
    return pair;
  }

  static final PeerDevice memberDevice = PeerDevice(
    peerId: testPeerId('b'),
    alias: 'member',
    platform: 'test',
    host: '192.168.1.9',
    port: 7890,
    seenAt: DateTime(2026),
  );

  Conversation get memberChat => memberStore.conversations.single;

  Future<void> verifyBothSides(String hostChat) async {
    host.markVerified(
      hostChat,
      expectedSas: hostStore.conversation(hostChat)!.sas,
    );
    member.markVerified(memberChat.id, expectedSas: memberChat.sas);
    await pumpEventQueue(times: 200);
  }
}

bool _hasEvent(InMemoryStore store, String id, SystemEventKind kind) =>
    store.messages(id).any((m) => m.systemEvent?.kind == kind);

void main() {
  test('a host-dialled unchecked link joins only after both check the code, '
      'so the member never gets room posts as 1:1 posts', () async {
    final p = await _Pair.create();
    final chat = await p.host.connectToPeer(_Pair.memberDevice);
    await pumpEventQueue(times: 200);

    await p.host.addPeersToRoom(chat, const []);
    await pumpEventQueue(times: 200);
    // 멤버가 거부할 room_join이면 호스트도 방으로 세지 않음
    expect(p.host.appRoomId, isNull);
    expect(p.hostStore.conversation(chat)!.isRoom, isFalse);
    expect(
      _hasEvent(p.hostStore, chat, SystemEventKind.roomWaitsVerification),
      isTrue,
    );

    await p.verifyBothSides(chat);
    expect(p.host.appRoomId, chat);
    expect(p.memberChat.isRoom, isTrue);
    expect(p.memberChat.hostPeerId, testPeerId('a'));
  });

  test(
    'picking the 1:1 peer again while making the room keeps its link',
    () async {
      final p = await _Pair.create();
      final chat = await p.host.connectToPeer(_Pair.memberDevice);
      await pumpEventQueue(times: 200);
      await p.verifyBothSides(chat);
      final dialsBefore = p.dials;

      await p.host.addPeersToRoom(chat, [_Pair.memberDevice]);
      await pumpEventQueue(times: 200);

      expect(p.dials, dialsBefore);
      expect(p.memberChat.isRoom, isTrue);
      expect(p.memberChat.online, isTrue);
      expect(p.host.linksForTransfer(chat), hasLength(1));
    },
  );
}
