// Separate QA-only entry point; never imported by the production application.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intragram/core/browser_received_files_web.dart';
import 'package:intragram/core/platform_files_web.dart';
import 'package:intragram/core/voice/voice_clip.dart';
import 'package:intragram/core/voice/voice_wav.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/store/vault.dart';
import 'package:web/web.dart' as web;

@JS('intragramBrowserQA')
external set _api(JSObject value);
@JS('intragramVoiceQA')
external set _voiceResult(JSString value);

const _path = 'intragram-private/browser-qa.json';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BrowserPrivateFiles.initialize();
  _api =
      {
            'write': ((JSString value) => _write(
              value.toDart,
            ).then((v) => v.toJS).toJS).toJS,
            'read': (() => File(
              _path,
            ).readAsString().then((v) => v.toJS).toJS).toJS,
            'erase': (() => File(
              _path,
            ).delete().then((_) => 'ok'.toJS).toJS).toJS,
            'reload':
                (() => BrowserPrivateFiles.initialize()
                        .then((_) => 'ok'.toJS)
                        .toJS)
                    .toJS,
            'vault': (() => _vault().then((v) => v.toJS).toJS).toJS,
            'files': (() => _files().toJS).toJS,
            'save': ((JSString value) => BrowserReceivedFiles.save(
              value.toDart,
            )).toJS,
            'clear': (() => BrowserReceivedFiles.clear()).toJS,
            'contains': ((JSString value) => BrowserReceivedFiles.contains(
              value.toDart,
            )).toJS,
            'opfsSession':
                (() => BrowserReceivedFiles.sessionDir()
                        .then((dir) => (dir != null).toJS)
                        .toJS)
                    .toJS,
            'opfsSweep':
                (() => BrowserReceivedFiles.sweepStaleTemp()
                        .then((_) => 'ok'.toJS)
                        .toJS)
                    .toJS,
          }.jsify()
          as JSObject;
  final button = web.HTMLButtonElement()..textContent = 'Run voice test';
  button.onclick = ((web.Event _) {
    unawaited(
      _voice().then(
        (value) => _voiceResult = value.toJS,
        onError: (Object error) => _voiceResult = 'ERROR $error'.toJS,
      ),
    );
  }).toJS;
  web.document.body!.appendChild(button);
  // Keep the button in the DOM rather than under a Flutter canvas.
  button.style.position = 'fixed';
  button.style.zIndex = '10000';
  runApp(const MaterialApp(home: Scaffold(body: Text('Browser platform QA'))));
}

Future<String> _write(String value) async {
  final temp = File('$_path.tmp');
  await temp.writeAsString(value);
  await temp.rename(_path);
  return 'ok';
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<String> _vault() async {
  final vault = Vault();
  await vault.erase();
  vault.setPin('123456');
  vault.setDecoyPin('654321');
  final snapshot = VaultSnapshot(
    settings: const VaultSettings(enabled: true, pinProtected: true),
    conversations: const [],
    transfers: const [],
    messages: [
      EphemeralMessage(
        id: 'qa',
        conversationId: 'qa',
        direction: MessageDirection.incoming,
        kind: MessageKind.text,
        senderAlias: 'QA',
        createdAt: DateTime.now(),
        text: 'private-한글-body',
        delivery: DeliveryState.read,
      ),
    ],
  );
  await vault.save(snapshot);
  final raw = await File('intragram-private/vault.json').readAsString();
  _expect(!raw.contains('private-한글-body'), 'vault body leaked');
  _expect((jsonDecode(raw) as Map)['enc'] == true, 'vault was not sealed');
  vault.dispose();
  await BrowserPrivateFiles.initialize();
  final reopened = Vault();
  _expect(await reopened.isEncrypted(), 'encrypted marker lost');
  _expect(await reopened.unlock('wrong!') == null, 'wrong PIN accepted');
  final correct = await reopened.unlock('123456');
  _expect(
    correct?.messages.single.text == 'private-한글-body',
    'round trip failed',
  );
  reopened.lock();
  final decoy = await reopened.unlock('654321');
  _expect(
    decoy != null && decoy.messages.isEmpty && reopened.isDecoyMode,
    'duress did not open an empty session',
  );
  await reopened.save(snapshot);
  _expect(
    await File('intragram-private/vault.json').readAsString() == raw,
    'duress overwrote the real archive',
  );
  await reopened.erase();
  reopened.dispose();
  return 'PASS native vault codec, PIN, encrypted storage and duress';
}

String _files() {
  final original = Uint8List.fromList([0, 1, 2, 253, 254, 255]);
  final path = BrowserReceivedFiles.put('검증.bin', original);
  original[0] = 99;
  _expect(BrowserReceivedFiles.read(path)![0] == 0, 'file ownership failed');
  final copy = BrowserReceivedFiles.read(path)!;
  copy[1] = 99;
  _expect(
    BrowserReceivedFiles.read(path)![1] == 1,
    'read copy ownership failed',
  );
  return path;
}

Future<String> _voice() async {
  final wav = PcmWav(
    samples: ByteData(16000 ~/ 4 * 2),
    sampleRate: 16000,
    channels: 1,
  );
  final header = Uint8List(44 + wav.pcm.length);
  final h = ByteData.sublistView(header)
    ..setUint32(4, 36 + wav.pcm.length, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 16000, Endian.little)
    ..setUint32(28, 32000, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(40, wav.pcm.length, Endian.little);
  const tags = {0: 'RIFF', 8: 'WAVE', 12: 'fmt ', 36: 'data'};
  tags.forEach((at, tag) {
    for (var i = 0; i < 4; i++) {
      h.setUint8(at + i, tag.codeUnitAt(i));
    }
  });
  final clip = await loadVoiceClip(header);
  final completed = Completer<void>();
  final subscription = clip.progress.listen((value) {
    if (value.completed && !completed.isCompleted) completed.complete();
  });
  await clip.play();
  await completed.future.timeout(const Duration(seconds: 5));
  await subscription.cancel();
  await clip.dispose();
  return 'PASS browser shared voice playback';
}
