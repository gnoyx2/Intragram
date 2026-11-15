// QA-only Flutter entry point. Never imported by the production application.
// Run with flutter run -d macos -t tool/web_peer_harness.dart and QA_SECRET.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/network/web_peer_evidence.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final harness = _Harness();
  await harness.start();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Intragram WebRTC QA · localhost:${harness.server.port}'),
        ),
      ),
    ),
  );
}

class _Harness {
  late HttpServer server;
  late WebPeerSession peer;
  late WebPeerEvidence proof;
  bool dialled = true;
  final messages = <String>[];
  final controls = <Map<String, dynamic>>[];
  final transfers = <String, WebPeerTransfer>{};
  final errors = <String>[];
  final secret = const String.fromEnvironment('QA_SECRET');

  Future<void> reset() async {
    messages.clear();
    controls.clear();
    transfers.clear();
    errors.clear();
    final identity = await AppIdentity.create();
    peer = WebPeerSession(
      onState: (state) {
        if (state == 'connected') {
          unawaited(
            proof
                .start(peer.sessionBinding, dialled: dialled)
                .catchError((Object e) => errors.add('$e')),
          );
        }
      },
      onMessage: messages.add,
      onControl: (control) {
        controls.add(control);
        unawaited(
          proof.receive(control).catchError((Object e) => errors.add('$e')),
        );
      },
      onTransfer: (value) {
        transfers[value.id] = value;
        if (value.bytes != null) {
          unawaited(
            proof
                .recordFile(value.id, value.bytes!)
                .catchError((Object e) => errors.add('$e')),
          );
        }
      },
      onError: (error) => errors.add('$error'),
    );
    proof = WebPeerEvidence(identity: identity, sendControl: peer.sendControl);
  }

  Future<void> start() async {
    if (secret.length < 16) throw StateError('QA_SECRET required');
    await reset();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    debugPrint('INTRAGRAM_QA_PORT=${server.port}');
    server.listen((request) async {
      if (request.headers.value('x-qa-secret') != secret ||
          request.headers.value('origin') != null) {
        request.response.statusCode = 403;
        await request.response.close();
        return;
      }
      try {
        final chunks = <int>[];
        await for (final chunk in request) {
          chunks.addAll(chunk);
          if (chunks.length > 5 * 1024 * 1024) throw StateError('too large');
        }
        final data = chunks.isEmpty
            ? <String, dynamic>{}
            : (jsonDecode(utf8.decode(chunks)) as Map).cast<String, dynamic>();
        final result = await action(request.uri.path, data);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result));
      } catch (error) {
        request.response.statusCode = 400;
        request.response.write(jsonEncode({'error': '$error'}));
      }
      await request.response.close();
    });
  }

  Future<Object?> action(String path, Map<String, dynamic> data) async {
    switch (path) {
      case '/raw-description':
        final pc = await createPeerConnection({'iceServers': []});
        await pc.createDataChannel('intragram-web-v1', RTCDataChannelInit());
        await pc.setLocalDescription(await pc.createOffer());
        await Future<void>.delayed(const Duration(seconds: 3));
        final description = await pc.getLocalDescription();
        await pc.close();
        await pc.dispose();
        return {'sdp': description?.sdp, 'type': description?.type};
      case '/create':
        dialled = true;
        return {'code': await peer.createOffer()};
      case '/join':
        dialled = false;
        return {'code': await peer.acceptOffer(data['code'] as String)};
      case '/answer':
        await peer.acceptAnswer(data['code'] as String);
      case '/text':
        return {'id': await peer.sendText(data['text'] as String)};
      case '/control':
        await peer.sendControl(
          (data['control'] as Map).cast<String, dynamic>(),
        );
      case '/file':
        final bytes = Uint8List.fromList(base64Decode(data['bytes'] as String));
        final id = await peer.offerBytes(data['name'] as String, bytes);
        proof.expectFile(id, bytes);
        return {'id': id};
      case '/accept':
        await peer.acceptFile(data['id'] as String);
      case '/reject':
        await peer.rejectFile(data['id'] as String);
      case '/cancel':
        await peer.cancelFile(data['id'] as String);
      case '/close':
        await peer.close();
      case '/reset':
        await peer.close();
        proof.clear();
        await reset();
      case '/proof-export':
        return {'bundle': await proof.exportBundle()};
      case '/proof-import':
        return {'valid': await proof.importBundle(data['bundle'] as String)};
      case '/proof-witness':
        return {'anchor': await proof.witnessBundle(data['bundle'] as String)};
      case '/stats':
        return [
          for (final report in await peer.getStats())
            {'id': report.id, 'type': report.type, 'values': report.values},
        ];
      case '/state':
        return {
          'state': peer.state,
          'sas': peer.verificationCode,
          'messages': messages,
          'controls': controls,
          'errors': errors,
          'identity': proof.peerId,
          'peerIdentity': proof.peerIdentity?.peerId,
          'proofs': [
            for (final entry in proof.evidence.entries)
              {'id': entry.attestation.subjectId, 'status': entry.status.name},
          ],
          'transfers': [
            for (final transfer in transfers.values)
              {
                'id': transfer.id,
                'name': transfer.name,
                'state': transfer.state,
                'size': transfer.size,
                'transferred': transfer.transferred,
                'direction': transfer.direction,
                if (transfer.bytes != null)
                  'bytes': base64Encode(transfer.bytes!),
              },
          ],
        };
      case '/quit':
        await peer.close();
        Timer(const Duration(milliseconds: 200), () => exit(0));
      default:
        throw StateError('unknown route');
    }
    return {'ok': true};
  }
}
