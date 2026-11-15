import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/org_auth.dart';
import 'package:intragram/network/web_peer_evidence.dart';

void main() {
  test(
    'reflected identity cannot authenticate our key or obtain credentials',
    () async {
      final identity = await AppIdentity.create();
      final sent = <Map<String, dynamic>>[];
      final evidence = WebPeerEvidence(
        identity: identity,
        sendControl: (frame) async => sent.add(frame),
      );
      addTearDown(evidence.clear);
      await evidence.start(base64Encode(List.filled(32, 7)));
      final reflected = sent.single;
      await evidence.setCredential(
        jsonEncode(
          (await issueDemoCredential(
            identity,
            org: 'Private affiliation',
            dept: 'Private department',
            role: 'Private role',
          )).toWire(),
        ),
      );
      sent.clear();
      await evidence.receive(reflected);
      expect(
        evidence.peerIdentity,
        isNull,
        reason: 'our signature does not prove possession by the opposite peer',
      );
      expect(
        sent.where((frame) => frame['k'] == 'org-credential'),
        isEmpty,
        reason: 'an echo of our identity must not disclose our affiliation',
      );
    },
  );
}
