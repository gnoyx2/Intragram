import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/store/models.dart';
import 'support/web_chat_rig.dart';
import 'web_peer_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WebChatRig host, first, second;
  late Directory directory;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('web-chat-files-');
    host = await WebChatRig.create('AA', directory: directory.path);
    first = await WebChatRig.create('BB', directory: directory.path);
    second = await WebChatRig.create('CC', directory: directory.path);
  });
  tearDown(() async {
    await host.dispose();
    await first.dispose();
    await second.dispose();
    directory.deleteSync(recursive: true);
  });

  test(
    'oversized voice-named files still require explicit recipient consent',
    () async {
      await host.connect(first);
      await host.bridge.offerBytes(
        host.room!,
        'voice-large.wav',
        Uint8List(kMaxVoiceNoteBytes + 1),
      );
      final received = first.store.transfers.single;
      expect(received.voice, isFalse);
      expect(received.state, TransferState.offered);
      expect(
        host.connections.single.channel.sent.where((m) => m.isBinary),
        isEmpty,
      );
      await expectLater(
        host.bridge.offerBytes(
          host.room!,
          'voice-recording.wav',
          Uint8List(kMaxVoiceNoteBytes + 1),
          voice: true,
        ),
        throwsA(isA<WebPeerProblem>()),
      );
    },
  );

  test(
    'outgoing voice keeps its own playable bytes after send buffers release',
    () async {
      await host.connect(first);
      final bytes = Uint8List.fromList([82, 73, 70, 70, 1, 2, 3, 4]);
      final expected = Uint8List.fromList(bytes);
      await host.bridge.offerBytes(
        host.room!,
        'voice-test.wav',
        bytes,
        voice: true,
      );
      bytes.fillRange(0, bytes.length, 0);
      await webPeerUntil(
        () => host.store.transfers.single.state == TransferState.complete,
      );
      expect(host.store.transfers.single.voiceBytes, expected);
      expect(first.store.transfers.single.voiceBytes, expected);
      final held = host.store.transfers.single.voiceBytes!;
      host.store.secureWipe();
      await host.store.drainDisposals();
      expect(held, everyElement(0));
    },
  );

  test(
    'member file fan-out requires host and recipient consent and preserves origin',
    () async {
      await host.connect(first);
      await host.connect(second);
      final bytes = Uint8List.fromList(List.generate(100037, (i) => i % 251));
      await first.bridge.offerBytes(first.room!, 'member.bin', bytes);
      await webPeerUntil(() => host.store.transfers.isNotEmpty);
      final original = host.store.transfers.single;
      expect(original.state, TransferState.offered);
      expect(second.store.transfers, isEmpty);
      expect(
        first.connections.single.channel.sent.where((data) => data.isBinary),
        isEmpty,
      );
      await host.bridge.accept(original.id);
      await webPeerUntil(() => second.store.transfers.isNotEmpty);
      final forwarded = second.store.transfers.single;
      expect(forwarded.state, TransferState.offered);
      expect(forwarded.senderPeerId, original.senderPeerId);
      expect(
        host.connections.last.channel.sent.where((data) => data.isBinary),
        isEmpty,
      );
      await second.bridge.accept(forwarded.id);
      await webPeerUntil(
        () =>
            second.store.transfer(forwarded.id)?.state ==
            TransferState.complete,
      );
      expect(
        await File(
          second.store.transfer(forwarded.id)!.localPath!,
        ).readAsBytes(),
        bytes,
      );
      expect(first.store.transfers, hasLength(1));
      await second.bridge.markRead(second.room!);
      await webPeerUntil(
        () =>
            first.store.messageById(original.id)?.delivery ==
            DeliveryState.read,
      );
      second.bridge.sendControl(second.room!, {
        'k': 'react',
        'id': forwarded.id,
        'emoji': '👍',
        'on': true,
      });
      await webPeerUntil(
        () => first.store.messageById(original.id)!.reactions.isNotEmpty,
      );
      first.bridge.sendControl(first.room!, {'k': 'burn', 'id': original.id});
      await webPeerUntil(() => second.store.messageById(forwarded.id) == null);
      expect(host.store.messageById(original.id), isNull);
      expect([...host.errors, ...first.errors, ...second.errors], isEmpty);
    },
  );

  test(
    'one owned snapshot safely fans out while caller bytes change',
    () async {
      await host.connect(first);
      await host.connect(second);
      final bytes = Uint8List.fromList(List.generate(300037, (i) => i % 251));
      final expected = Uint8List.fromList(bytes);
      await host.bridge.offerBytes(host.room!, 'shared.bin', bytes);
      bytes.fillRange(0, bytes.length, 0);
      await webPeerUntil(
        () =>
            first.store.transfers.isNotEmpty &&
            second.store.transfers.isNotEmpty,
      );
      await first.bridge.accept(first.store.transfers.single.id);
      await second.bridge.accept(second.store.transfers.single.id);
      await webPeerUntil(
        () =>
            first.store.transfers.single.state == TransferState.complete &&
            second.store.transfers.single.state == TransferState.complete,
      );
      expect(
        await File(first.store.transfers.single.localPath!).readAsBytes(),
        expected,
      );
      expect(
        await File(second.store.transfers.single.localPath!).readAsBytes(),
        expected,
      );
    },
  );

  test(
    'send budget caps active snapshots and evicts old finished retry bytes',
    () async {
      await host.connect(first);
      final bytes = Uint8List(60 * 1024 * 1024);
      await host.bridge.offerBytes(host.room!, 'first.bin', bytes);
      await webPeerUntil(() => first.store.transfers.isNotEmpty);
      await expectLater(
        host.bridge.offerBytes(host.room!, 'too-much.bin', bytes),
        throwsA(isA<WebPeerProblem>()),
      );
      await first.bridge.reject(first.store.transfers.single.id);
      await webPeerUntil(
        () => host.store.transfers.single.state == TransferState.rejected,
      );
      await host.bridge.offerBytes(host.room!, 'replacement.bin', bytes);
      await webPeerUntil(() => first.store.transfers.length == 2);
      expect(first.store.transfers.last.state, TransferState.offered);
      await host.bridge.closeRoom(host.room!);
      expect(host.store.transfers.last.state, TransferState.failed);
    },
  );
}
