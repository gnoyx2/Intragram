import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/store/models.dart';

import 'support/web_chat_rig.dart';
import 'web_peer_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a transfer in flight ends as failed on both sides when the link drops',
    () async {
      final directory = Directory.systemTemp.createTempSync('web-link-drop-');
      final host = await WebChatRig.create('AA', directory: directory.path);
      final guest = await WebChatRig.create('BB', directory: directory.path);
      addTearDown(() async {
        await host.dispose();
        await guest.dispose();
        directory.deleteSync(recursive: true);
      });
      await host.connect(guest);
      await host.bridge.offerBytes(
        host.room!,
        'drop.bin',
        Uint8List(2 * 1024 * 1024),
      );
      await webPeerUntil(() => guest.store.transfers.isNotEmpty);
      // 보내는 쪽 버퍼를 꽉 찬 것처럼 둬서 수락 뒤에도 전송이 진행 중에 머물게 함
      host.connections.single.channel.buffer = 1 << 30;
      await guest.bridge.accept(guest.store.transfers.single.id);
      TransferState? stateOf(WebChatRig rig) =>
          rig.store.transfers.single.state;
      await webPeerUntil(() => stateOf(host) == TransferState.transferring);
      await guest.connections.single.channel.close();
      await host.connections.single.channel.close();
      await webPeerUntil(
        () =>
            stateOf(host) == TransferState.failed &&
            stateOf(guest) == TransferState.failed,
      );
    },
  );
}
