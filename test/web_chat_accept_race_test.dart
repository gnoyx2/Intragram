import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/store/models.dart';

import 'support/web_chat_rig.dart';
import 'web_peer_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 수락 뒤 폴더 선택기가 떠 있는 동안 보낸 쪽이 취소함: 선택을 마쳐도 수락이 되살아나면 안 됨
  test('a sender cancel while the folder picker is open is not revived '
      'as accepted', () async {
    final outbox = Directory.systemTemp.createTempSync('web-race-out-');
    final inbox = Directory.systemTemp.createTempSync('web-race-in-');
    final picker = Completer<String?>();
    final sender = await WebChatRig.create('AA');
    final receiver = await WebChatRig.create(
      'BB',
      chooseDirectory: (_) => picker.future,
    );
    addTearDown(() async {
      await sender.dispose();
      await receiver.dispose();
      outbox.deleteSync(recursive: true);
      inbox.deleteSync(recursive: true);
    });
    await sender.connect(receiver);
    final file = File('${outbox.path}/race.bin')..writeAsBytesSync([1, 2, 3]);
    await sender.bridge.offerPaths(sender.room!, [file.path]);
    await webPeerUntil(() => receiver.store.transfers.isNotEmpty);
    final id = receiver.store.transfers.single.id;

    final accepting = receiver.bridge.accept(id).catchError((Object _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sender.bridge.cancel(sender.store.transfers.single.id);
    await webPeerUntil(
      () => receiver.store.transfer(id)!.state == TransferState.cancelled,
    );
    picker.complete(inbox.path);
    await accepting;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(receiver.store.transfer(id)!.state, TransferState.cancelled);
    expect(inbox.listSync(), isEmpty);
  });
}
