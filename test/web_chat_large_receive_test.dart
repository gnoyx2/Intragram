import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/constants.dart' show kMaxInlineMessageBytes;
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/store/models.dart';

import 'support/web_chat_rig.dart';
import 'web_peer_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('receiver LargeMessageMode decides inbound text above 1 MiB', () async {
    final sender = await WebChatRig.create('AA');
    final receiver = await WebChatRig.create('BB');
    addTearDown(() async {
      await sender.dispose();
      await receiver.dispose();
    });
    await sender.connect(receiver);
    sender.store.largeMessageMode = LargeMessageMode.unlimited;

    // Native inline/spill receivers drop text above 1 MiB; WebRTC must match.
    final dropped = 'd' * (kMaxInlineMessageBytes + 1);
    await sender.bridge.sendText(sender.room!, dropped);
    await sender.bridge.sendText(sender.room!, 'after the large text');
    await webPeerUntil(
      () => receiver.store
          .messages(receiver.room!)
          .any((m) => m.text == 'after the large text'),
    );
    expect(
      receiver.store.messages(receiver.room!).any((m) => m.text == dropped),
      isFalse,
    );

    receiver.store.largeMessageMode = LargeMessageMode.unlimited;
    final accepted = 'u' * (kMaxInlineMessageBytes + 1);
    await sender.bridge.sendText(sender.room!, accepted);
    await webPeerUntil(
      () => receiver.store
          .messages(receiver.room!)
          .any((m) => m.text == accepted),
    );
    expect(sender.errors, isEmpty);
    expect(receiver.errors, isEmpty);
  });
}
