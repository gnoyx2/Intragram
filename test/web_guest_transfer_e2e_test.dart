import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/local_server.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/portal_guest.dart' show identity;

// Browser wire frames over real WebSocket/HTTP, including the receiver's disk.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late Directory dir;
  late InMemoryStore store;
  late LinkRegistry registry;
  late LocalServer server;
  late HttpClient client;
  late WebSocket guest;
  late Uri base;
  late List<Map<String, dynamic>> frames;

  Future<void> until(bool Function() predicate) async {
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (!predicate()) {
      if (DateTime.now().isAfter(end)) throw TimeoutException('guest transfer');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  void send(Map<String, dynamic> inner) =>
      guest.add(jsonEncode({'t': 'plain', 'd': inner}));

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('intragram_web_e2e');
    store = InMemoryStore();
    registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: identity(),
      chooseDirectory: (_) async => dir.path,
    );
    server = LocalServer(
      registry: registry,
      identity: identity(),
      onInboundError: (error, _) => fail('$error'),
      preferredPort: 0,
      bindAddress: InternetAddress.loopbackIPv4,
    )..portalToken = 'web-e2e-token';
    final bound = (await server.start())!;
    registry.localEndpoint = bound;
    base = Uri.parse('http://${bound.host}:${bound.port}');
    client = HttpClient();
    frames = [];
    guest = await WebSocket.connect(
      'ws://${bound.host}:${bound.port}/ws',
      headers: {'Origin': base.origin},
    );
    guest.listen((raw) {
      final frame = jsonDecode(raw as String) as Map<String, dynamic>;
      if (frame['t'] == 'plain') {
        frames.add((frame['d'] as Map).cast<String, dynamic>());
      }
    });
    guest.add(
      jsonEncode({
        't': 'web_hello',
        'v': kProtocolVersion,
        'alias': 'browser-e2e',
        'tok': 'web-e2e-token',
      }),
    );
    await until(() => frames.any((frame) => frame['k'] == 'room_state'));
  });

  tearDown(() async {
    await guest.close();
    client.close(force: true);
    await server.stop();
    await registry.disposeAll();
    store.dispose();
    dir.deleteSync(recursive: true);
  });

  test('browser upload is accepted, saved exactly and cannot replay', () async {
    final bytes = Uint8List.fromList(
      List<int>.generate(300037, (i) => i % 251),
    );
    send({
      'k': 'file_offer',
      'id': 'browser-upload',
      'at': 'upload-attempt',
      'md': 'push',
      'name': '한글-browser.bin',
      'size': bytes.length,
    });
    await until(() => store.transfer('browser-upload') != null);
    await registry.acceptTransfer('browser-upload');
    await until(() => frames.any((frame) => frame['k'] == 'file_accept'));
    final accepted = frames.firstWhere((frame) => frame['k'] == 'file_accept');
    Future<int> upload() async {
      final req = await client.postUrl(base.resolve('/api/transfer'));
      req.headers
        ..set('x-transfer-id', 'browser-upload')
        ..set('x-transfer-attempt', 'upload-attempt')
        ..set('x-transfer-token', accepted['tok'])
        ..set('x-file-size', '${bytes.length}');
      req.add(bytes);
      final response = await req.close();
      await response.drain<void>();
      return response.statusCode;
    }

    expect(await upload(), 200);
    await until(
      () => store.transfer('browser-upload')!.state == TransferState.complete,
    );
    final file = File(store.transfer('browser-upload')!.localPath!);
    expect(await file.readAsBytes(), bytes);
    expect(await upload(), 403);
    expect(await file.readAsBytes(), bytes);
  });

  test(
    'native file downloads exactly and completes only after browser ACK',
    () async {
      final bytes = Uint8List.fromList(utf8.encode('앱 → 브라우저 파일\n' * 20000));
      await registry.offerInlineBytes(registry.portalRoomId!, '앱.txt', bytes);
      await until(() => frames.any((frame) => frame['k'] == 'file_offer'));
      final offer = frames.firstWhere((frame) => frame['k'] == 'file_offer');
      expect(offer['md'], 'pull');
      final req = await client.getUrl(
        base.resolve('/api/download/${offer['id']}'),
      );
      req.headers
        ..set('x-transfer-attempt', offer['at'])
        ..set('x-transfer-token', offer['tok'])
        ..set('x-file-size', '${offer['size']}');
      final response = await req.close();
      expect(response.statusCode, 200);
      final received = await response.fold<List<int>>([], (all, chunk) {
        all.addAll(chunk);
        return all;
      });
      expect(received, bytes);
      expect(store.transfer(offer['id'])!.state, isNot(TransferState.complete));
      send({'k': 'file_received', 'id': offer['id'], 'at': offer['at']});
      await until(
        () => store.transfer(offer['id'])!.state == TransferState.complete,
      );
    },
  );
}
