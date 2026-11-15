part of 'web_peer_evidence.dart';

extension WebPeerOrganization on WebPeerEvidence {
  Future<void> setTrustBundle(String text) async {
    if (text.length > 256 * 1024) throw const WebPeerProblem('invalid-frame');
    final raw = jsonDecode(text);
    if (raw is! Map ||
        wireId(raw['id']) == null ||
        raw['snapshot'] is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw['snapshot']) ||
        raw['issuers'] is! List ||
        (raw['issuers'] as List).length > 64 ||
        raw['revoked'] != null && raw['revoked'] is! List) {
      throw const WebPeerProblem('invalid-frame');
    }
    final issuers = <TrustedIssuer>[];
    final ids = <String>{};
    for (final issuer in raw['issuers']) {
      final key = issuer is Map ? wireBytes(issuer['key'], length: 32) : null;
      if (key == null ||
          wireId(issuer['id']) == null ||
          issuer['name'] is! String ||
          issuer['id'].length > 128 ||
          issuer['name'].length > 96 ||
          issuer['name'].trim().isEmpty ||
          !ids.add(issuer['id']) ||
          issuer['policies'] is! List ||
          (issuer['policies'] as List).isEmpty ||
          (issuer['policies'] as List).length > 64 ||
          (issuer['policies'] as List).any(
            (p) =>
                p is! String ||
                !RegExp(r'^[a-z0-9][a-z0-9/:._-]{0,63}$').hasMatch(p),
          )) {
        throw const WebPeerProblem('invalid-frame');
      }
      issuers.add(
        TrustedIssuer(
          id: issuer['id'],
          name: issuer['name'],
          key: key,
          policies: (issuer['policies'] as List).cast<String>().toSet(),
          demo: issuer['demo'] == true,
        ),
      );
    }
    final revoked = (raw['revoked'] as List? ?? []).cast<Object?>();
    if (revoked.length > 4096 || revoked.any((id) => wireId(id) == null)) {
      throw const WebPeerProblem('invalid-frame');
    }
    _trust = TrustBundle(
      id: raw['id'],
      snapshot: raw['snapshot'],
      issuers: issuers,
      revoked: revoked.cast<String>().toSet(),
    );
    if (_presentation != null) {
      await _receiveOrganization(_presentation!, _generation);
    }
    _scheduleOrganizationExpiry();
    onChange?.call();
  }

  Future<void> clearCredential() async {
    if (credential == null) return;
    credential = null;
    await sendControl({'k': 'org-credential', 'credential': null});
    onChange?.call();
  }

  Future<void> setCredential(String text) async {
    final generation = _generation;
    if (text.length > 8192) throw const WebPeerProblem('invalid-frame');
    final parsed = OrgCredential.fromWire(jsonDecode(text));
    if (parsed == null ||
        base64Encode(parsed.subjectKey) != publicKey ||
        !await parsed.issuerSigned() ||
        DateTime.now().millisecondsSinceEpoch >= parsed.expiresAtMs) {
      throw const WebPeerProblem('invalid-frame');
    }
    if (generation != _generation ||
        base64Encode(parsed.subjectKey) != publicKey) {
      return;
    }
    credential = parsed;
    _scheduleOrganizationExpiry();
    await presentCredential();
    onChange?.call();
  }

  Future<void> presentCredential() async {
    final remote = peerIdentity, holder = credential;
    if (remote == null ||
        holder == null ||
        _binding.isEmpty ||
        DateTime.now().millisecondsSinceEpoch >= holder.expiresAtMs) {
      return;
    }
    final generation = _generation;
    final proof = await identity.sign(
      orgPopBytes(
        credentialDigest: holder.digest,
        policy: holder.policy,
        sessionBinding: base64Decode(_binding),
        holderDialled: _dialled,
        holderPeerId: identity.peerId,
        verifierPeerId: remote.peerId,
      ),
    );
    if (generation != _generation || !identical(credential, holder)) return;
    await sendControl({
      'k': 'org-credential',
      'credential': holder.toWire(),
      'credentialDigest': holder.digest,
      'policy': holder.policy,
      'pop': base64Encode(proof),
    });
  }
}

extension _WebPeerOrganizationReceive on WebPeerEvidence {
  Future<void> _receiveOrganization(
    Map<String, dynamic> raw,
    int generation,
  ) async {
    if (raw['credential'] == null) {
      _organization = null;
      _presentation = null;
      return;
    }
    final remote = peerIdentity, trust = _trust;
    final holder = OrgCredential.fromWire(raw['credential']);
    final pop = wireBytes(raw['pop'], length: 64);
    if (remote == null ||
        holder == null ||
        pop == null ||
        raw['credentialDigest'] != holder.digest ||
        raw['policy'] != holder.policy) {
      return;
    }
    _presentation = raw;
    if (trust == null) {
      _organization = OrgCredentialStatus(
        check: OrgCheck.untrustedIssuer,
        credential: holder,
      );
      return;
    }
    final status = await verifyOrgPresentation(
      credential: holder,
      pop: pop,
      bundle: trust,
      holderPeerId: remote.peerId,
      verifierPeerId: identity.peerId,
      sessionBinding: base64Decode(_binding),
      holderDialled: !_dialled,
    );
    if (generation == _generation &&
        identical(trust, _trust) &&
        identical(raw, _presentation)) {
      _organization = status;
    }
  }

  void _scheduleOrganizationExpiry() {
    _expiryTimer?.cancel();
    final at = DateTime.now().millisecondsSinceEpoch;
    final holder = credential;
    if (holder != null && holder.expiresAtMs <= at) {
      credential = null;
      if (_binding.isNotEmpty) {
        unawaited(
          sendControl({'k': 'org-credential'}).catchError((Object _) {}),
        );
      }
    }
    _organization = organization;
    final deadlines = [
      if (credential != null) credential!.expiresAtMs,
      if (_organization?.verified == true)
        _organization!.credential.expiresAtMs,
    ];
    if (deadlines.isEmpty) return;
    final deadline = deadlines.reduce((a, b) => a < b ? a : b);
    _expiryTimer = Timer(Duration(milliseconds: deadline - at), () {
      _scheduleOrganizationExpiry();
      onChange?.call();
    });
  }
}
