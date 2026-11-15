import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intragram/audit/content_commitment.dart' show sha256B64;
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/network/web_peer_evidence.dart';
import 'package:intragram/network/web_stream_io.dart';
import 'package:intragram/store/models.dart';

import 'support/web_chat_rig.dart';
import 'web_peer_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late WebPeerSession left, right;
  late WebPeerFakeConnection a, b;
  late List<WebPeerTransfer> sent, received;
  late List<Object> errors;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('web-peer-stream-');
    a = WebPeerFakeConnection('AA');
    b = WebPeerFakeConnection('BB');
    a.channel.peer = b.channel;
    b.channel.peer = a.channel;
    sent = [];
    received = [];
    errors = [];
    left = WebPeerSession(
      connectionFactory: (_) async => a,
      onTransfer: sent.add,
      onError: errors.add,
    );
    right = WebPeerSession(
      connectionFactory: (_) async => b,
      onTransfer: received.add,
      onError: errors.add,
    );
  });

  tearDown(() async {
    await left.close();
    await right.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> connect() async {
    final offer = await left.createOffer();
    final answer = await right.acceptOffer(offer);
    b.onDataChannel!(b.channel);
    await left.acceptAnswer(answer);
    a.channel.open();
    b.channel.open();
    await webPeerUntil(
      () => left.state == 'connected' && right.state == 'connected',
    );
  }

  test(
    'streams multi-MiB file with 4 MiB credit window, incremental SHA-256, and signed receipt',
    () async {
      await connect();
      final leftId = await AppIdentity.create();
      final rightId = await AppIdentity.create();
      late WebPeerEvidence leftProof, rightProof;
      leftProof = WebPeerEvidence(
        identity: leftId,
        sendControl: (c) => rightProof.receive(c),
      );
      rightProof = WebPeerEvidence(
        identity: rightId,
        sendControl: (c) => leftProof.receive(c),
      );
      final binding = left.sessionBinding;
      await Future.wait([
        leftProof.start(binding, dialled: true),
        rightProof.start(binding, dialled: false),
      ]);
      final bytes = Uint8List.fromList(
        List.generate(6 * 1024 * 1024 + 331, (i) => (i * 31 + 7) & 0xff),
      );
      final expectedDigest = sha256B64(bytes);
      final srcFile = File('${tempDir.path}/source.bin')
        ..writeAsBytesSync(bytes);
      final outDir = Directory('${tempDir.path}/out')..createSync();

      String? senderDigest;
      final source = await webSourceFromPath(srcFile.path);
      final id = await left.offerStream(
        'large-video.mp4',
        source,
        onDigest: (d) => senderDigest = d,
      );
      await webPeerUntil(() => received.isNotEmpty);
      expect(received.single.state, 'offered');
      expect(received.single.size, bytes.length);

      final sink = await openWebReceiveSink(
        'large-video.mp4',
        bytes.length,
        chooseDirectory: (_) async => outDir.path,
        wanted: () => true,
      );
      expect(sink, isNotNull);
      await right.acceptFileStream(id, sink!, wanted: () => true);

      await webPeerUntil(
        () =>
            sent.isNotEmpty &&
            sent.last.state == 'complete' &&
            received.last.state == 'complete',
      );
      expect(senderDigest, expectedDigest);
      expect(received.last.sha256B64, expectedDigest);
      leftProof.expectFileDigest(id, senderDigest!);
      await rightProof.recordFileDigest(id, received.last.sha256B64!);
      await webPeerUntil(() => leftProof.evidence.entries.isNotEmpty);
      expect(received.last.localPath, isNotNull);
      expect(await File(received.last.localPath!).readAsBytes(), bytes);
      // Verify file-credit frames were exchanged for > 4 MiB stream.
      final credits = b.channel.sent
          .where((m) => !m.isBinary)
          .map((m) => jsonDecode(m.text) as Map)
          .where((f) => f['kind'] == 'file-credit')
          .toList();
      expect(credits, isNotEmpty);
      expect(outDir.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
      expect(errors, isEmpty);
    },
  );

  test(
    'mid-stream cancel aborts sink and removes partial file cleanly',
    () async {
      await connect();
      // Infinite-ish paused stream to hold transfer mid-stream.
      Stream<List<int>> slowChunks() async* {
        yield Uint8List(64 * 1024);
        await Future<void>.delayed(const Duration(seconds: 5));
        yield Uint8List(64 * 1024);
      }

      final outDir = Directory('${tempDir.path}/cancel-out')..createSync();
      final source = StreamWebByteSource(128 * 1024, slowChunks);
      final id = await left.offerStream('partial.bin', source);
      await webPeerUntil(() => received.isNotEmpty);
      final sink = await openWebReceiveSink(
        'partial.bin',
        128 * 1024,
        chooseDirectory: (_) async => outDir.path,
        wanted: () => true,
      );
      await right.acceptFileStream(id, sink!, wanted: () => true);
      await webPeerUntil(() => received.last.transferred == 64 * 1024);
      await left.cancelFile(id);
      await webPeerUntil(() => received.last.state == 'cancelled');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(outDir.listSync(), isEmpty);
    },
  );

  test(
    'falls back to 20-byte chunks for <=100 MiB non-stream accept and rejects >100 MiB non-stream accept',
    () async {
      await connect();
      final payload = Uint8List.fromList(List.generate(40000, (i) => i & 0xff));
      final source = MemoryWebByteSource(payload);
      final id = await left.offerStream('compat.bin', source);
      await webPeerUntil(() => received.isNotEmpty);
      // Legacy peer (like lite.html) accepts WITHOUT stream: true!
      await right.acceptFile(id);
      await webPeerUntil(
        () =>
            sent.last.state == 'complete' && received.last.state == 'complete',
      );
      expect(received.last.bytes, payload);

      // Now offer >100 MiB stream, and simulate legacy peer sending file-accept without stream: true.
      final hugeSource = StreamWebByteSource(
        webPeerMaxFileBytes + 1024,
        () => const Stream.empty(),
      );
      final hugeId = await left.offerStream('huge.bin', hugeSource);
      await webPeerUntil(() => received.last.id == hugeId);
      a.channel.onMessage!(
        RTCDataChannelMessage(
          jsonEncode({'kind': 'file-accept', 'id': hugeId}),
        ),
      );
      await webPeerUntil(() => sent.last.state == 'failed');
      expect(
        errors.single,
        isA<WebPeerProblem>().having((e) => e.code, 'code', 'peer-file-limit'),
      );
    },
  );

  test(
    'WebChatBridge streams offerPaths through group host relay with signed receipts',
    () async {
      final hostOut = Directory('${tempDir.path}/host')..createSync();
      final secondOut = Directory('${tempDir.path}/second')..createSync();
      final host = await WebChatRig.create('AA', directory: hostOut.path);
      final first = await WebChatRig.create('BB', directory: tempDir.path);
      final second = await WebChatRig.create('CC', directory: secondOut.path);
      addTearDown(() async {
        await host.dispose();
        await first.dispose();
        await second.dispose();
      });
      await host.connect(first);
      await host.connect(second);
      final payload = Uint8List.fromList(
        List.generate(5 * 1024 * 1024 + 97, (i) => (i * 13 + 3) & 0xff),
      );
      final src = File('${tempDir.path}/streamed.bin')
        ..writeAsBytesSync(payload);
      await first.bridge.offerPaths(first.room!, [src.path]);
      await webPeerUntil(() => host.store.transfers.isNotEmpty);
      await host.bridge.accept(host.store.transfers.single.id);
      await webPeerUntil(() => second.store.transfers.isNotEmpty);
      await second.bridge.accept(second.store.transfers.single.id);
      await webPeerUntil(
        () => second.store.transfers.single.state == TransferState.complete,
      );
      final hostIncoming = host.store.transfers.singleWhere(
        (t) => t.direction == TransferDirection.incoming,
      );
      expect(await File(hostIncoming.localPath!).readAsBytes(), payload);
      expect(
        await File(second.store.transfers.single.localPath!).readAsBytes(),
        payload,
      );
      expect([...host.errors, ...first.errors, ...second.errors], isEmpty);
    },
  );
}
