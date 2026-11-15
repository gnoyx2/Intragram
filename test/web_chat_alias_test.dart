import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/store/models.dart';

import 'support/web_chat_rig.dart';
import 'web_peer_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('both sides of a 1:1 label received text with the sender name', () async {
    final inviter = await WebChatRig.create('AA');
    final joiner = await WebChatRig.create('BB');
    addTearDown(() async {
      await inviter.dispose();
      await joiner.dispose();
    });
    await inviter.connect(joiner);
    await webPeerUntil(
      () =>
          joiner.store.conversation(joiner.room!)!.peerAlias ==
              inviter.identity.alias &&
          inviter.store.conversation(inviter.room!)!.peerAlias ==
              joiner.identity.alias,
    );

    await inviter.bridge.sendText(inviter.room!, 'from the inviter');
    await joiner.bridge.sendText(joiner.room!, 'from the joiner');
    EphemeralMessage? received(WebChatRig rig, String text) =>
        rig.store.messages(rig.room!).where((m) => m.text == text).firstOrNull;
    await webPeerUntil(
      () =>
          received(joiner, 'from the inviter') != null &&
          received(inviter, 'from the joiner') != null,
    );
    // A 1:1 bubble hides the name, but search, the vault and a later room show it.
    expect(
      received(joiner, 'from the inviter')!.senderAlias,
      inviter.identity.alias,
    );
    expect(
      received(inviter, 'from the joiner')!.senderAlias,
      joiner.identity.alias,
    );
    expect([...inviter.errors, ...joiner.errors], isEmpty);
  });
}
