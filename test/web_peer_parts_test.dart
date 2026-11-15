import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intragram/core/constants.dart'
    show kMaxFrameBytes, kMaxInlineMessageBytes, kSpillThresholdBytes;
import 'package:intragram/network/room_integrity.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/network/web_peer_protocol.dart'
    show
        WebPeerProblem,
        webPeerMakeStreamChunk,
        webPeerParseFrame,
        webPeerParseStreamChunk;
import 'package:intragram/store/models.dart';

import 'support/web_chat_rig.dart';
import 'web_peer_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'multi-part UTF-8 text reassembly, replay dedupe, 64-bit stream chunk offsets, and malformed part rejection',
    () async {
      final a = WebPeerFakeConnection('AA');
      final b = WebPeerFakeConnection('BB');
      a.channel.peer = b.channel;
      b.channel.peer = a.channel;
      final frames = <Map<String, dynamic>>[];
      final errors = <Object>[];
      final left = WebPeerSession(
        connectionFactory: (_) async => a,
        onError: errors.add,
      );
      final right = WebPeerSession(
        connectionFactory: (_) async => b,
        onTextFrame: frames.add,
        onError: errors.add,
      );
      addTearDown(() async {
        await left.close();
        await right.close();
      });

      final offer = await left.createOffer();
      final answer = await right.acceptOffer(offer);
      b.onDataChannel!(b.channel);
      await left.acceptAnswer(answer);
      a.channel.open();
      b.channel.open();
      await webPeerUntil(
        () => left.state == 'connected' && right.state == 'connected',
      );

      final unit = '한글🚀"줄바꿈"\n';
      final unitBytes = utf8.encode(unit).length;
      final repeats = kMaxInlineMessageBytes ~/ unitBytes;
      final pad = 'a' * (kMaxInlineMessageBytes - repeats * unitBytes);
      final oneMiB = '${unit * repeats}$pad';
      expect(utf8.encode(oneMiB).length, kMaxInlineMessageBytes);

      final id = await left.sendText(oneMiB, maxBytes: kMaxInlineMessageBytes);
      await webPeerUntil(() => frames.length == 1);
      expect(frames.single['id'], id);
      expect(frames.single['text'], oneMiB);
      expect(errors, isEmpty);

      // Replay of part 0 with an already-seen message id is ignored cleanly.
      final firstSent = a.channel.sent.first;
      b.channel.onMessage!(firstSent);
      expect(frames, hasLength(1));
      expect(errors, isEmpty);

      // 64-bit stream chunk offsets above 4 GiB round-trip cleanly.
      const bigOffset = 5 * 1024 * 1024 * 1024 + 17;
      final payload = Uint8List.fromList([1, 2, 3, 4, 255]);
      final encodedChunk = webPeerMakeStreamChunk('a' * 32, bigOffset, payload);
      final parsedChunk = webPeerParseStreamChunk(encodedChunk);
      expect(parsedChunk.id, 'a' * 32);
      expect(parsedChunk.offset, bigOffset);
      expect(parsedChunk.bytes, payload);

      // Out-of-order part index fails the session cleanly.
      final badPart = jsonEncode({
        'kind': 'part',
        'id': 'b' * 32,
        'target': 'text',
        'index': 1,
        'count': 2,
        'total': 10,
        'data': base64Encode([65, 66, 67, 68, 69]),
      });
      expect(webPeerParseFrame(badPart)['kind'], 'part');
      b.channel.onMessage!(RTCDataChannelMessage(badPart));
      await webPeerUntil(() => right.state == 'closed');
      expect(errors.single, isA<WebPeerProblem>());
    },
  );

  test(
    'WebChatBridge enforces LargeMessageMode inline, spillToFile, and unlimited across 1:1 and signed groups',
    () async {
      final host = await WebChatRig.create('AA');
      final first = await WebChatRig.create('BB');
      final second = await WebChatRig.create('CC');
      addTearDown(() async {
        await host.dispose();
        await first.dispose();
        await second.dispose();
      });

      await host.connect(first);
      await host.connect(second);
      await webPeerUntil(() => first.store.conversation(first.room!)!.isRoom);

      // Default inline mode: > 1 MiB fails locally without breaking connection.
      final overInline = 'x' * (kMaxInlineMessageBytes + 1);
      await first.bridge.sendText(first.room!, overInline);
      final failedMsg = first.store.messages(first.room!).single;
      expect(failedMsg.delivery, DeliveryState.failed);
      expect(host.store.messages(host.room!), isEmpty);

      // Inline mode: 200 KiB signed multi-byte group message arrives verified.
      final multiPartText = '그룹장문🧪한글\n' * 12000;
      expect(utf8.encode(multiPartText).length, greaterThan(150 * 1024));
      await first.bridge.sendText(first.room!, multiPartText);
      await webPeerUntil(
        () =>
            host.store.messages(host.room!).length == 1 &&
            second.store.messages(second.room!).length == 1,
      );
      expect(host.store.messages(host.room!).single.text, multiPartText);
      expect(second.store.messages(second.room!).single.text, multiPartText);
      expect(
        host.store.roomIntegrity.status(host.room!),
        RoomIntegrityStatus.verified,
      );
      expect(
        second.store.roomIntegrity.status(second.room!),
        RoomIntegrityStatus.verified,
      );

      // spillToFile mode: > 64 KiB text converts to message.txt file offer.
      host.store.largeMessageMode = LargeMessageMode.spillToFile;
      final spillText = '파일전환📝' * ((kSpillThresholdBytes ~/ 10) + 500);
      expect(utf8.encode(spillText).length, greaterThan(kSpillThresholdBytes));
      await host.bridge.sendText(host.room!, spillText);
      await webPeerUntil(
        () => first.store.transfers.any(
          (t) => t.conversationId == first.room! && t.fileName == 'message.txt',
        ),
      );

      // unlimited mode on both ends: > 1 MiB text arrives inline. Like native v7, a receiver
      // still in inline mode refuses a frame above 2 MiB at its first part instead of buffering it.
      host.store.largeMessageMode = LargeMessageMode.unlimited;
      first.store.largeMessageMode = LargeMessageMode.unlimited;
      final twoMiB = '무제한🔥\n' * 190000;
      expect(utf8.encode(twoMiB).length, greaterThan(kMaxFrameBytes));
      await host.bridge.sendText(host.room!, twoMiB);
      await webPeerUntil(
        () =>
            first.store.messages(first.room!).any((m) => m.text == twoMiB) &&
            second.errors.isNotEmpty,
      );
      expect(host.errors, isEmpty);
      expect(first.errors, isEmpty);
      expect(second.errors.map((e) => '$e'), [contains('invalid-frame')]);
      expect(
        second.store.messages(second.room!).any((m) => m.text == twoMiB),
        isFalse,
      );
    },
  );

  test(
    'WebChatBridge supports >8 guest peers up to 31 guest links (32 members) and rejects the 32nd',
    () async {
      final host = await WebChatRig.create('AA');
      final guests = <WebChatRig>[];
      addTearDown(() async {
        for (final g in guests) {
          await g.dispose();
        }
        await host.dispose();
      });

      for (var i = 0; i < 10; i++) {
        final guest = await WebChatRig.create(
          (i + 16).toRadixString(16).toUpperCase().padLeft(2, '0'),
        );
        guests.add(guest);
        await host.connect(guest);
      }
      await webPeerUntil(
        () => host.store.conversation(host.room!)!.memberCount == 11,
      );
      await guests.first.bridge.sendText(
        guests.first.room!,
        '11-member signed check',
      );
      await webPeerUntil(
        () => guests.last.store
            .messages(guests.last.room!)
            .any((m) => m.text == '11-member signed check'),
      );
      expect(
        guests.last.store.roomIntegrity.status(guests.last.room!),
        RoomIntegrityStatus.verified,
      );

      // Allocate remaining 21 pending guest offers (10 connected + 21 pending = 31 guest links = 32 members).
      for (var i = 10; i < 31; i++) {
        await host.bridge.createInvitation(conversationId: host.room);
      }
      await expectLater(
        host.bridge.createInvitation(conversationId: host.room),
        throwsA(
          isA<WebPeerProblem>().having((e) => e.code, 'code', 'room-full'),
        ),
      );
    },
  );
}
