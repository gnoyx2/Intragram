part of 'web_peer_evidence.dart';

extension _WebPeerEvidenceReceive on WebPeerEvidence {
  Future<void> _receive(Map<String, dynamic> control) async {
    final generation = _generation;
    if (_binding.isEmpty) return;
    switch (control['k']) {
      case 'identity':
        final key = wireBytes(control['pk'], length: 32);
        final signature = wireBytes(control['sg'], length: 64);
        if (key == null ||
            base64Encode(key) == publicKey ||
            signature == null ||
            !await verifyEd25519(
              message: utf8.encode(
                jsonEncode([
                  'intragram/web-identity/v1',
                  _binding,
                  control['pk'],
                ]),
              ),
              signature: signature,
              key: key,
            )) {
          return;
        }
        if (generation != _generation) return;
        final known = peerIdentity;
        if (known != null && known.peerId != peerIdOfKey(key)) return;
        peerIdentity = (peerId: peerIdOfKey(key), key: key);
        // Let the connection reject a blocked identity before sending credentials.
        onChange?.call();
        if (generation == _generation) await presentCredential();
        return;
      case 'attestation':
        final value = SignedAttestation.fromWire(control['value']);
        final remote = peerIdentity;
        if (value == null ||
            remote == null ||
            value.signerPeerId != remote.peerId ||
            value.attemptId != _attempt ||
            value.counterpartId != identity.peerId ||
            base64Encode(value.counterpartKey ?? []) != publicKey) {
          return;
        }
        final bound =
            value.kind != AttestationKind.deliveryCommitted ||
            _expectedFiles[value.subjectId] == value.commitment;
        final signed = await value.verify();
        if (generation != _generation) return;
        if (signed &&
            value.kind == AttestationKind.deliveryCommitted &&
            !_expectedFiles.containsKey(value.subjectId)) {
          _pendingReceipts[value.eventId] = value;
          if (_pendingReceipts.length > 512) {
            _pendingReceipts.remove(_pendingReceipts.keys.first);
          }
          return;
        }
        final valid = bound && signed;
        evidence.record(value, verified: valid, transferId: value.subjectId);
      case 'org-credential':
        await _receiveOrganization(control, generation);
      default:
        return;
    }
    if (generation == _generation) {
      _scheduleOrganizationExpiry();
      onChange?.call();
    }
  }
}
