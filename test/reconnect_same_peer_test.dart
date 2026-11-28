import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/test_identities.dart';

// 확인한 1:1이 끊긴 뒤 배너 말고 홈 타일·IP로 다시 붙어도 대화가 하나로 남아야 함
void main() {
  late InMemoryStore aStore, bStore;
  late LinkRegistry a, b;
  StreamChannelController<dynamic>? wire;
  final device = PeerDevice(
    peerId: testPeerId('b'),
    alias: 'member',
    platform: 'test',
    host: '192.168.1.9',
    port: 7890,
    seenAt: DateTime(2026),
  );
  setUp(() {
    aStore = InMemoryStore();
    bStore = InMemoryStore();
    a = LinkRegistry(
      store: aStore,
      crypto: CryptoEngine(),
      identity: testIdentity('a', alias: 'dialer', platform: 'test'),
    );
    b = LinkRegistry(
      store: bStore,
      crypto: CryptoEngine(),
      identity: testIdentity('b', alias: 'member', platform: 'test'),
    );
    a.debugDial = (_) async {
      final next = wire = StreamChannelController<dynamic>();
      await b.acceptInbound(next.foreign, remoteHost: '192.168.1.1');
      return next.local;
    };
  });
  tearDown(() async {
    await a.disposeAll();
    await b.disposeAll();
    aStore.dispose();
    bStore.dispose();
  });

  List<Conversation> chats(InMemoryStore store) =>
      store.conversations.where((c) => !c.isRoom).toList();

  Future<String> checkedThenDropped() async {
    final chat = await a.connectToPeer(device);
    await pumpEventQueue(times: 200);
    final other = chats(bStore).single;
    a.markVerified(chat, expectedSas: aStore.conversation(chat)!.sas);
    b.markVerified(other.id, expectedSas: other.sas);
    await pumpEventQueue(times: 200);
    await wire!.local.sink.close();
    await pumpEventQueue(times: 200);
    expect(aStore.conversation(chat)!.online, isFalse);
    return chat;
  }

  test('tapping the same device again reuses its checked chat', () async {
    final chat = await checkedThenDropped();
    expect(await a.connectToPeer(device), chat);
    await pumpEventQueue(times: 200);
    expect(chats(aStore).map((c) => c.id), [chat]);
    expect(aStore.conversation(chat)!.online, isTrue);
    expect(chats(bStore), hasLength(1));
  });

  test(
    'connecting by IP to the same device lands in its checked chat',
    () async {
      final chat = await checkedThenDropped();
      expect(await a.connectManual(host: '192.168.1.9', port: 7890), chat);
      await pumpEventQueue(times: 200);
      expect(chats(aStore).map((c) => c.id), [chat]);
      expect(chats(bStore), hasLength(1));
    },
  );
}
