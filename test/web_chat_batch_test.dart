import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/store/models.dart';
import 'support/web_chat_rig.dart';
import 'web_peer_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WebChatRig host, guest;
  late Directory inbox, outbox;
  late List<String> paths;
  setUp(() async {
    inbox = Directory.systemTemp.createTempSync('web-batch-in-');
    outbox = Directory.systemTemp.createTempSync('web-batch-out-');
    paths = [
      for (final (name, text) in [
        ('one.txt', 'first'),
        ('둘.txt', 'second 두번째'),
        ('three.txt', 'third'),
      ])
        (File('${outbox.path}/$name')..writeAsStringSync(text)).path,
    ];
    host = await WebChatRig.create('AA', directory: inbox.path);
    guest = await WebChatRig.create('BB', directory: inbox.path);
    await host.connect(guest);
  });
  tearDown(() async {
    await host.dispose();
    await guest.dispose();
    inbox.deleteSync(recursive: true);
    outbox.deleteSync(recursive: true);
  });

  List<FileTransfer> offered(WebChatRig rig) => rig.store.transfers
      .where((t) => t.direction == TransferDirection.incoming)
      .toList();

  test(
    'files picked together arrive as one batch the receiver accepts at once',
    () async {
      await host.bridge.offerPaths(host.room!, paths);
      await webPeerUntil(() => offered(guest).length == 3);
      final batchIds = offered(guest).map((t) => t.batchId).toSet();
      expect(batchIds, hasLength(1));
      expect(batchIds.single, isNotNull);
      expect(offered(guest).map((t) => t.state).toSet(), {
        TransferState.offered,
      });
      expect(
        host.store.transfers.map((t) => t.batchLabel),
        containsAll(['1 / 3', '2 / 3', '3 / 3']),
      );
      expect(
        host.connections.single.channel.sent.where((m) => m.isBinary),
        isEmpty,
        reason: 'no file content before consent',
      );

      await guest.bridge.acceptBatch(guest.room!, batchIds.single!);
      await webPeerUntil(
        () =>
            host.store.transfers.every(
              (t) => t.state == TransferState.complete,
            ) &&
            offered(guest).every((t) => t.state == TransferState.complete),
      );
      for (final path in paths) {
        final name = path.split('/').last;
        expect(
          File('${inbox.path}/$name').readAsStringSync(),
          File(path).readAsStringSync(),
        );
      }
    },
  );

  test('decline all refuses every file of the batch without bytes', () async {
    await host.bridge.offerPaths(host.room!, paths);
    await webPeerUntil(() => offered(guest).length == 3);
    await guest.bridge.rejectBatch(guest.room!, offered(guest).first.batchId!);
    await webPeerUntil(
      () =>
          host.store.transfers.every((t) => t.state == TransferState.rejected),
    );
    expect(
      host.connections.single.channel.sent.where((m) => m.isBinary),
      isEmpty,
    );
    expect(inbox.listSync(), isEmpty);
  });

  test('a single file is still offered without a batch', () async {
    await host.bridge.offerPaths(host.room!, paths.take(1).toList());
    await webPeerUntil(() => offered(guest).length == 1);
    expect(offered(guest).single.batchId, isNull);
    expect(host.store.transfers.single.batchLabel, isNull);
  });

  // 상한을 넘는 파일 하나 때문에 같이 고른 파일이 막히면 안 됨: 그 파일만 빼고 보냄 (sparse라 디스크를 안 씀).
  // 알림은 제안을 시작하기 전에 옴 (하나씩 받는 상대면 앞 파일이 다 갈 때까지 늦어질 수 있어서)
  test('a file over the limit is left out and the others still go', () async {
    final huge = File('${outbox.path}/huge.bin');
    huge.openSync(mode: FileMode.write)
      ..truncateSync(webPeerMaxStreamFileBytes + 1)
      ..closeSync();
    final noticed = <int>[];

    await host.bridge.offerPaths(host.room!, [
      huge.path,
      ...paths.take(2),
    ], onTooLarge: () => noticed.add(host.store.transfers.length));

    expect(noticed, [0], reason: 'once, before any file was offered');
    await webPeerUntil(() => offered(guest).length == 2);
    expect(offered(guest).map((t) => t.fileName), isNot(contains('huge.bin')));
    expect(offered(guest).map((t) => t.batchId).toSet(), hasLength(1));
    expect(
      host.store.transfers.map((t) => t.batchLabel),
      containsAll(['1 / 2', '2 / 2']),
    );
  });

  // 고른 뒤 지워진 파일 하나도 나머지를 막지 않음: 나머지를 보낸 뒤 그 오류를 알림
  test('an unreadable file does not cancel the rest of the pick', () async {
    final gone = '${outbox.path}/deleted-after-pick.txt';

    await expectLater(
      host.bridge.offerPaths(host.room!, [gone, ...paths.take(2)]),
      throwsA(isA<FileSystemException>()),
    );

    await webPeerUntil(() => offered(guest).length == 2);
    expect(
      host.store.transfers.map((t) => t.batchLabel),
      containsAll(['1 / 2', '2 / 2']),
    );
  });
}
