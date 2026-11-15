import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:intragram/audit/anchor_bundle.dart';
import 'package:intragram/audit/content_commitment.dart';
import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/org_auth.dart';
import 'package:intragram/network/protocol.dart' show wireBytes, wireId;
import 'package:intragram/network/web_peer_protocol.dart';

part 'web_peer_evidence_org.dart';
part 'web_peer_evidence_receive.dart';

// These signatures prove application statements, not physical erasure or OS download success.
class WebPeerEvidence {
  WebPeerEvidence({
    required this.identity,
    required this.sendControl,
    this.onChange,
  }) {
    evidence.bindSigner(identity);
  }
  final AppIdentity identity;
  final Future<void> Function(Map<String, dynamic>) sendControl;
  final void Function()? onChange;
  final evidence = EvidenceStore();
  final _expectedFiles = <String, String>{};
  ({String peerId, Uint8List key})? peerIdentity;
  String _binding = '';
  bool _dialled = true;
  int _generation = 0;
  int _queued = 0;
  Future<void> _receiving = Future<void>.value();
  final _pendingReceipts = <String, SignedAttestation>{};
  OrgCredential? credential;
  TrustBundle? _trust;
  OrgCredentialStatus? _organization;
  Timer? _expiryTimer;
  OrgCredentialStatus? get organization {
    final status = _organization;
    if (status != null &&
        status.verified &&
        DateTime.now().millisecondsSinceEpoch >=
            status.credential.expiresAtMs) {
      return OrgCredentialStatus(
        check: OrgCheck.expired,
        credential: status.credential,
        issuerName: status.issuerName,
        demo: status.demo,
      );
    }
    return status;
  }

  Map<String, dynamic>? _presentation;

  String get publicKey => base64Encode(identity.publicKey!);
  String get peerId => identity.peerId;
  String get _attempt =>
      base64UrlEncode(base64Decode(_binding)).replaceAll('=', '');

  Future<void> start(String sessionBinding, {bool dialled = true}) async {
    if (wireBytes(sessionBinding, length: 32) == null) {
      throw const WebPeerProblem('invalid-frame');
    }
    if (_binding.isNotEmpty &&
        (_binding != sessionBinding || _dialled != dialled)) {
      throw const WebPeerProblem('session-in-use');
    }
    _binding = sessionBinding;
    _dialled = dialled;
    final generation = _generation;
    final pk = publicKey;
    final signature = await identity.sign(
      utf8.encode(jsonEncode(['intragram/web-identity/v1', _binding, pk])),
    );
    if (generation != _generation || _binding != sessionBinding) return;
    await sendControl({
      'k': 'identity',
      'pk': pk,
      'sg': base64Encode(signature),
    });
  }

  Future<void> receive(Map<String, dynamic> control) {
    if (_queued >= 32) return Future<void>.value();
    final generation = _generation;
    _queued++;
    final operation = _receiving.then((_) async {
      if (generation == _generation) await _receive(control);
    });
    _receiving = operation
        .catchError((Object _) {})
        .whenComplete(() => _queued--);
    return operation;
  }

  void expectFile(String id, Uint8List bytes) =>
      expectFileDigest(id, sha256B64(bytes));

  void expectFileDigest(String id, String digestB64) {
    _expectedFiles[id] = digestB64;
    final pending = _pendingReceipts.values
        .where((a) => a.subjectId == id)
        .toList();
    for (final a in pending) {
      _pendingReceipts.remove(a.eventId);
      unawaited(receive({'k': 'attestation', 'value': a.toWire()}));
    }
    if (_expectedFiles.length > 512) {
      _expectedFiles.remove(_expectedFiles.keys.first);
    }
  }

  Future<void> recordFile(String id, Uint8List bytes) => recordFileDigest(
    id,
    sha256B64(bytes),
    policy: 'delivery/web-ram',
    outcome: 'buffered',
  );

  Future<void> recordFileDigest(
    String id,
    String digestB64, {
    String policy = 'delivery/web-stream',
    String outcome = 'persisted',
  }) =>
      _issue(AttestationKind.deliveryCommitted, id, digestB64, policy, outcome);

  Future<void> recordBurn(String id, String text) => _issue(
    AttestationKind.burnTriggered,
    id,
    saltedCommitment('intragram/web-burn/v1', [id, text]),
    'burn/web-memory',
    'triggered',
  );

  Future<void> _issue(
    AttestationKind kind,
    String id,
    String digest,
    String policy,
    String outcome,
  ) async {
    final remote = peerIdentity;
    if (_binding.isEmpty || remote == null) return;
    final generation = _generation;
    final signed = await evidence.issue(
      AttestationDraft(
        kind: kind,
        subjectId: id,
        attemptId: _attempt,
        counterpartId: remote.peerId,
        counterpartKey: remote.key,
        commitment: digest,
        policy: policy,
        outcome: outcome,
      ),
      transferId: id,
    );
    if (generation != _generation || signed == null) return;
    await sendControl({'k': 'attestation', 'value': signed.toWire()});
    if (generation == _generation) onChange?.call();
  }

  Future<String> exportBundle() async {
    final batch = await evidence.seal() ?? evidence.batches.lastOrNull;
    if (batch == null) throw const WebPeerProblem('invalid-frame');
    return exportAnchorBundle(evidence, batch);
  }

  Future<bool> importBundle(String text) async =>
      (await verifyAnchorBundle(text)).ok;

  Future<String> witnessBundle(String text) async {
    if (!(await verifyAnchorBundle(text)).ok) {
      throw const WebPeerProblem('invalid-frame');
    }
    final header = BatchHeader.fromWire((jsonDecode(text) as Map)['batch'])!;
    return jsonEncode((await AnchorReceipt.witness(identity, header)).toWire());
  }

  Future<bool> attachAnchor(String text, String witnessPeerId) async {
    if (text.length > 4096) return false;
    try {
      final receipt = AnchorReceipt.fromWire(jsonDecode(text));
      return receipt != null &&
          await evidence.attachAnchor(receipt, witnessPeerId: witnessPeerId);
    } on Object {
      return false;
    }
  }

  void clear() {
    _generation++;
    _binding = '';
    _expectedFiles.clear();
    _pendingReceipts.clear();
    peerIdentity = null;
    credential = null;
    _organization = null;
    _expiryTimer?.cancel();
    _presentation = null;
    evidence.clear();
    onChange?.call();
  }
}
