import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/network/web_peer_protocol.dart'
    show webPeerOutgoingName;

import 'support/web_chat_rig.dart';
import 'web_peer_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a picked file whose name has a slash or backslash is still offered',
    () async {
      final host = await WebChatRig.create('AA');
      final guest = await WebChatRig.create('BB');
      addTearDown(() async {
        await host.dispose();
        await guest.dispose();
      });
      await host.connect(guest);
      await host.bridge.offerBytes(
        host.room!,
        r'dq\back.txt',
        Uint8List.fromList([1, 2, 3]),
      );
      await webPeerUntil(() => guest.store.transfers.isNotEmpty);
      expect(guest.store.transfers.single.fileName, 'dq_back.txt');
      expect(webPeerOutgoingName(r'a/b\c.txt'), 'a_b_c.txt');
    },
  );
}
