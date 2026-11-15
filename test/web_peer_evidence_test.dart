import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/audit/anchor_bundle.dart';
import 'package:intragram/audit/evidence_entry.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/org_auth.dart';
import 'package:intragram/network/web_peer_evidence.dart';

Future<AppIdentity> _identity(int byte) async {
  final seed = Uint8List.fromList(List.filled(32, byte));
  final pair = await Ed25519().newKeyPairFromSeed(seed);
  return AppIdentity.withKey(
    seed: seed,
    publicKey: (await pair.extractPublicKey()).bytes,
    alias: 'native',
    platform: 'test',
  );
}

void main() {
  test(
    'native and browser signatures, receipt hashes, audit Merkle bundles and organization PoP interoperate',
    () async {
      final identity = await _identity(1);
      final binding = base64Encode(List.filled(32, 7)),
          binding2 = base64Encode(List.filled(32, 8));
      final controls = <Map<String, dynamic>>[];
      final native = WebPeerEvidence(
        identity: identity,
        sendControl: (c) async => controls.add(c),
      );
      final process = await Process.start('node', [
        'test/web_peer_evidence_vectors.mjs',
      ]);
      final stderr = process.stderr.transform(utf8.decoder).join();
      final lines = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      addTearDown(() {
        process.kill();
        native.clear();
      });
      void send(Map<String, dynamic> value) =>
          process.stdin.writeln(jsonEncode(value));
      Future<Map<String, dynamic>> read() async {
        if (!await lines.moveNext().timeout(const Duration(seconds: 15))) {
          throw StateError(await stderr);
        }
        return (jsonDecode(lines.current) as Map).cast<String, dynamic>();
      }

      send({'binding': binding, 'binding2': binding2});
      final browser = await read();
      await native.start(binding);
      await native.receive(
        (browser['identity'] as Map).cast<String, dynamic>(),
      );
      expect(native.peerIdentity?.peerId, browser['peerId']);
      final browserHolder = AppIdentity.withKey(
        seed: List.filled(32, 0),
        publicKey: base64Decode(browser['publicKey']),
        alias: 'browser',
        platform: 'Web',
      );
      final demo = await demoTrustBundle();
      final trust = jsonEncode({
        'id': demo.id,
        'snapshot': demo.snapshot,
        'issuers': [
          for (final i in demo.issuers)
            {
              'id': i.id,
              'name': i.name,
              'key': base64Encode(i.key),
              'policies': i.policies.toList(),
              'demo': i.demo,
            },
        ],
        'revoked': demo.revoked.toList(),
      });
      await native.setTrustBundle(trust);
      await native.setCredential(
        jsonEncode(
          (await issueDemoCredential(
            identity,
            org: 'Demo',
            dept: 'QA',
            role: 'Test',
          )).toWire(),
        ),
      );
      final browserCredential = await issueDemoCredential(
        browserHolder,
        org: 'Demo',
        dept: 'Browser',
        role: 'Test',
      );
      final bytes = Uint8List.fromList(List.generate(100037, (i) => i % 251));
      final outgoing = 'a' * 32, incoming = 'b' * 32;
      native.expectFile(outgoing, bytes);
      await native.recordFile(incoming, bytes);
      final bundle = await native.exportBundle();
      expect((await verifyAnchorBundle(bundle)).ok, true);
      send({
        'identity': controls.firstWhere((c) => c['k'] == 'identity'),
        'peerId': identity.peerId,
        'bytes': base64Encode(bytes),
        'receipt': controls.firstWhere((c) => c['k'] == 'attestation'),
        'organization': controls.firstWhere((c) => c['k'] == 'org-credential'),
        'trust': trust,
        'browserCredential': jsonEncode(browserCredential.toWire()),
        'bundle': bundle,
        'outgoingId': outgoing,
      });
      final result = await read();
      await native.receive((result['receipt'] as Map).cast<String, dynamic>());
      expect(
        native.evidence.entries
            .where((e) => e.status == EvidenceStatus.verified)
            .length,
        1,
      );
      await native.receive(
        (result['organization'] as Map).cast<String, dynamic>(),
      );
      expect(native.organization?.verified, true);
      expect(native.organization?.demo, true);
      expect(await native.importBundle(result['bundle']), true);
      final copied = jsonDecode(result['bundle']);
      copied['batch']['no'] = 999;
      expect(await native.importBundle(jsonEncode(copied)), false);
      final fresh = WebPeerEvidence(
        identity: identity,
        sendControl: (c) async {},
      );
      await fresh.start(binding2);
      await fresh.receive((browser['identity'] as Map).cast<String, dynamic>());
      await fresh.receive((result['receipt'] as Map).cast<String, dynamic>());
      expect(fresh.peerIdentity, isNull);
      expect(fresh.evidence.entries, isEmpty);
      fresh.clear();
      await process.stdin.close();
      expect(
        await process.exitCode.timeout(const Duration(seconds: 10)),
        0,
        reason: await stderr,
      );
      await lines.cancel();
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
