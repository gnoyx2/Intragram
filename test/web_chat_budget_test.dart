import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/store/models.dart';
import 'support/web_chat_rig.dart';
import 'web_peer_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WebChatRig host, guest;
  late Directory inbox;
  setUp(() async {
    inbox = Directory.systemTemp.createTempSync('web-budget-in-');
    host = await WebChatRig.create('AA', directory: inbox.path);
    guest = await WebChatRig.create('BB', directory: inbox.path);
    await host.connect(guest);
  });
  tearDown(() async {
    webChatStaleOfferAge = const Duration(minutes: 2);
    await host.dispose();
    await guest.dispose();
    inbox.deleteSync(recursive: true);
  });

  List<FileTransfer> sent() => host.store.transfers
      .where((t) => t.direction == TransferDirection.outgoing)
      .toList();
  List<FileTransfer> offered() => guest.store.transfers
      .where((t) => t.direction == TransferDirection.incoming)
      .toList();

  test('a silent receiver holds the send budget only until its offers go '
      'stale', () async {
    final chunk = Uint8List(30 << 20);
    for (var i = 0; i < 3; i++) {
      await host.bridge.offerBytes(host.room!, '$i.bin', chunk);
    }
    await webPeerUntil(() => offered().length == 3);
    await expectLater(
      host.bridge.offerBytes(host.room!, '3.bin', chunk),
      throwsA(
        isA<WebPeerProblem>().having((e) => e.code, 'code', 'send-budget'),
      ),
      reason: 'fresh unanswered offers keep their bytes',
    );

    webChatStaleOfferAge = Duration.zero;
    await host.bridge.offerBytes(host.room!, '3.bin', chunk);
    await webPeerUntil(() => offered().length == 4);
    String stateOf(List<FileTransfer> list, String name) =>
        list.lastWhere((t) => t.fileName == name).state.name;
    await webPeerUntil(() => stateOf(offered(), '0.bin') == 'cancelled');
    expect(stateOf(sent(), '0.bin'), 'cancelled');
    for (final name in ['1.bin', '2.bin', '3.bin']) {
      expect(stateOf(offered(), name), 'offered', reason: name);
    }
    expect(inbox.listSync(), isEmpty);
  });
}
