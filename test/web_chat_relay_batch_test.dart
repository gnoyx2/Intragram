import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/store/models.dart';
import 'support/web_chat_rig.dart';
import 'web_peer_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WebChatRig host, first, second;
  late Directory hostDir, secondDir, outbox;
  late List<String> paths;
  setUp(() async {
    hostDir = Directory.systemTemp.createTempSync('web-relay-host-');
    secondDir = Directory.systemTemp.createTempSync('web-relay-second-');
    outbox = Directory.systemTemp.createTempSync('web-relay-out-');
    paths = [
      for (final (name, text) in [
        ('one.txt', 'first'),
        ('둘.txt', 'second 두번째'),
        ('three.txt', 'third'),
      ])
        (File('${outbox.path}/$name')..writeAsStringSync(text)).path,
    ];
    host = await WebChatRig.create('AA', directory: hostDir.path);
    first = await WebChatRig.create('BB', directory: outbox.path);
    second = await WebChatRig.create('CC', directory: secondDir.path);
    await host.connect(first);
    await host.connect(second);
  });
  tearDown(() async {
    await host.dispose();
    await first.dispose();
    await second.dispose();
    for (final dir in [hostDir, secondDir, outbox]) {
      dir.deleteSync(recursive: true);
    }
  });

  List<FileTransfer> offered(WebChatRig rig) => rig.store.transfers
      .where((t) => t.direction == TransferDirection.incoming)
      .toList();

  test(
    'a member batch is relayed as one batch the other members accept at once',
    () async {
      await first.bridge.offerPaths(first.room!, paths);
      await webPeerUntil(() => offered(host).length == 3);
      expect(second.store.transfers, isEmpty, reason: 'host consent first');
      await host.bridge.acceptBatch(host.room!, offered(host).first.batchId!);
      await webPeerUntil(() => offered(second).length == 3);
      final relayed = offered(second).map((t) => t.batchId).toSet();
      expect(relayed, hasLength(1));
      expect(relayed.single, isNotNull);
      expect(offered(second).map((t) => t.state).toSet(), {
        TransferState.offered,
      });

      await second.bridge.acceptBatch(second.room!, relayed.single!);
      await webPeerUntil(
        () => offered(second).every((t) => t.state == TransferState.complete),
      );
      for (final path in paths) {
        final name = path.split('/').last;
        expect(
          File('${secondDir.path}/$name').readAsStringSync(),
          File(path).readAsStringSync(),
        );
      }
      expect([...host.errors, ...first.errors, ...second.errors], isEmpty);
    },
  );

  // v7 방처럼 수신자별로 줄 섬: 답하지 않는 멤버 하나가 다른 멤버의 파일을 막지 않음
  test('an unanswered offer to one member does not hold back others', () async {
    await host.bridge.offerPaths(host.room!, [paths[0]]);
    await webPeerUntil(
      () => offered(first).length == 1 && offered(second).length == 1,
    );
    await second.bridge.accept(offered(second).single.id);
    await webPeerUntil(
      () => offered(second).single.state == TransferState.complete,
    );
    unawaited(host.bridge.offerPaths(host.room!, [paths[2]]));
    await webPeerUntil(() => offered(second).length == 2);
    // 동시 전송을 아는 멤버(앱·Flutter 웹)는 v7처럼 두 번째 제안도 바로 받음
    await webPeerUntil(() => offered(first).length == 2);
    expect(offered(first).map((t) => t.state).toSet(), {TransferState.offered});
  });

  test(
    'a member that never announced lanes keeps one offer at a time',
    () async {
      final toFirst = host.sessions.first;
      await webPeerUntil(() => toFirst.peerLanes > 1);
      toFirst.peerLanes = 1;
      await host.bridge.offerPaths(host.room!, [paths[0]]);
      await webPeerUntil(
        () => offered(first).length == 1 && offered(second).length == 1,
      );
      await second.bridge.accept(offered(second).single.id);
      await webPeerUntil(
        () => offered(second).single.state == TransferState.complete,
      );
      // 이 호출은 답 없는 멤버에게도 제안할 때까지 끝나지 않음
      unawaited(host.bridge.offerPaths(host.room!, [paths[2]]));
      await webPeerUntil(() => offered(second).length == 2);
      expect(offered(first).map((t) => t.state), [TransferState.offered]);
    },
  );

  test('a declined relayed batch writes nothing on that member', () async {
    await first.bridge.offerPaths(first.room!, paths);
    await webPeerUntil(() => offered(host).length == 3);
    await host.bridge.acceptBatch(host.room!, offered(host).first.batchId!);
    await webPeerUntil(() => offered(second).length == 3);
    await second.bridge.rejectBatch(
      second.room!,
      offered(second).first.batchId!,
    );
    await webPeerUntil(
      () => offered(second).every((t) => t.state == TransferState.rejected),
    );
    expect(secondDir.listSync(), isEmpty);
  });
}
