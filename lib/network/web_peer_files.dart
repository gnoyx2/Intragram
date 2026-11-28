part of 'web_peer.dart';

// 바이트·응답이 이만큼 없으면 전송을 실패로 끝냄 (v7 EOF 뒤 ACK 25초와 같은 몫). 테스트만 줄여 씀
Duration webPeerTransferTimeout = const Duration(seconds: 30);

// file-end 뒤 받는 쪽 커밋(flush·fsync·이름 바꾸기)을 기다릴 때 가정하는 최저 저장 속도. 테스트만 바꿈
int webPeerCommitBytesPerSecond = 16 * 1024 * 1024;

extension _WebPeerFileInternals on WebPeerSession {
  void _transfer(
    _Transfer transfer, [
    Uint8List? bytes,
    String? localPath,
    String? sha256B64,
  ]) {
    onTransfer?.call(
      WebPeerTransfer(
        id: transfer.id,
        name: transfer.name,
        direction: transfer.direction,
        // 상대가 수락했고 자리(받는 쪽이든 보내는 쪽이든)만 기다리는 제안은 '답 없는 제안'과 구별해 알림
        state:
            transfer.state == 'offered' &&
                (transfer.accepted || transfer.peerQueued)
            ? 'accepted'
            : transfer.state,
        size: transfer.size,
        transferred: transfer.transferred,
        bytes: bytes,
        origin: transfer.origin,
        alias: transfer.alias,
        localPath: localPath ?? transfer.localPath,
        sha256B64: sha256B64 ?? transfer.sha256B64,
        stream: transfer.streamOffer,
        batch: transfer.batch,
      ),
    );
  }

  void _finish(
    _Transfer transfer,
    String next, [
    Uint8List? bytes,
    String? localPath,
    String? sha256B64,
  ]) {
    transfer.timer?.cancel();
    transfer.timer = null;
    final waiter = transfer.creditWaiter;
    transfer.creditWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    final sink = transfer.sink;
    transfer.sink = null;
    if (sink != null) unawaited(sink.abort().catchError((Object _) {}));
    transfer.hashSink = null;
    transfer.source = null;
    transfer.localPath = localPath ?? transfer.localPath;
    transfer.sha256B64 = sha256B64 ?? transfer.sha256B64;
    transfer.state = next;
    transfer.start = null;
    transfer.chunks?.clear();
    transfer.chunks = null;
    transfer.bytes = null;
    _dequeue(transfer);
    _transfer(transfer, bytes, transfer.localPath, transfer.sha256B64);
  }

  void _transferDeadline(_Transfer transfer, [Duration? timeout]) {
    transfer.timer?.cancel();
    if (!_active.contains(transfer.state)) return;
    transfer.timer = Timer(
      timeout ?? webPeerTransferTimeout,
      () => _abandon(transfer),
    );
  }

  // 이 파일만 실패로 끝내고 상대에게 취소를 알림 (링크는 그대로)
  void _abandon(_Transfer transfer, [Object? error]) {
    if (!_active.contains(transfer.state)) return;
    unawaited(
      _send({
        'kind': 'file-cancel',
        'id': transfer.id,
      }).catchError((Object _) {}),
    );
    _finish(transfer, 'failed');
    if (error != null) onError?.call(error);
  }

  // 보낸 쪽이 file-end 뒤 file-done을 기다리는 기한: 큰 파일은 받는 쪽 fsync가 30초를 넘을 수 있어 크기에 비례해 늘림
  void _awaitCommit(_Transfer transfer) => _transferDeadline(
    transfer,
    webPeerTransferTimeout +
        Duration(seconds: transfer.size ~/ webPeerCommitBytesPerSecond),
  );

  Future<void> _backpressure() async {
    final channel = _channel;
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw const WebPeerProblem('not-connected');
    }
    final end = DateTime.now().add(const Duration(seconds: 30));
    // Query native SCTP's buffer, not only the delayed platform event snapshot.
    while (await channel.getBufferedAmount() > _bufferLimit) {
      if (_channel != channel || state != 'connected') {
        throw const WebPeerProblem('session-closed');
      }
      if (DateTime.now().isAfter(end)) {
        throw const WebPeerProblem('transfer-timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (_channel != channel || state != 'connected') {
      throw const WebPeerProblem('session-closed');
    }
  }

  Future<void> _stream(_Transfer transfer) async {
    try {
      while (transfer.transferred < transfer.size &&
          transfer.state == 'transferring') {
        await _backpressure();
        if (transfer.state != 'transferring') return;
        final bytes = transfer.bytes;
        if (bytes == null) throw const WebPeerProblem('invalid-file-data');
        final end = (transfer.transferred + webPeerChunkBytes).clamp(
          0,
          transfer.size,
        );
        final chunk = webPeerMakeChunk(
          transfer.id,
          transfer.transferred,
          Uint8List.sublistView(bytes, transfer.transferred, end),
        );
        await _sendRaw(RTCDataChannelMessage.fromBinary(chunk));
        if (transfer.state != 'transferring') return;
        transfer.transferred = end;
        _transfer(transfer);
      }
      if (transfer.state != 'transferring') return;
      await _backpressure();
      if (transfer.state != 'transferring') return;
      transfer.ended = true;
      await _send({'kind': 'file-end', 'id': transfer.id});
      _awaitCommit(transfer);
    } on Object catch (error) {
      _abandon(transfer, error);
    }
  }
}

extension _WebPeerFiles on WebPeerSession {
  // 앞 제안이 아직 오가면 묶음 제안이나 동시 전송을 아는 상대에게만 제안을 더 걺
  void _checkOutgoingRoom(String? batch) {
    if (_outbound.isEmpty) return;
    if (batch == null && peerLanes < 2 ||
        _outbound.length > webPeerMaxWaitingOffers) {
      throw const WebPeerProblem('transfer-busy');
    }
  }

  Future<String> _offerBytes(
    String name,
    Uint8List bytes, {
    bool copy = true,
    String? id,
    String? origin,
    String? alias,
    String? batch,
  }) async {
    _checkOutgoingRoom(batch);
    id ??= webPeerNewId();
    name = webPeerOutgoingName(name);
    final frame = {
      'kind': 'file-offer',
      'id': id,
      'name': name,
      'size': bytes.length,
      'origin': ?origin,
      'alias': ?alias,
      'bid': ?batch,
    };
    try {
      webPeerParseFrame(jsonEncode(frame));
    } on Object {
      throw const WebPeerProblem('invalid-file');
    }
    final transfer = _Transfer(
      id: id,
      name: name,
      direction: 'send',
      size: bytes.length,
      bytes: copy ? Uint8List.fromList(bytes) : bytes.asUnmodifiableView(),
      batch: batch,
    );
    if (_outbound.containsKey(id)) throw const WebPeerProblem('invalid-file');
    _outbound[id] = transfer;
    try {
      await _send(frame);
    } on Object {
      _finish(transfer, 'failed');
      rethrow;
    }
    if (transfer.state == 'offered') _transfer(transfer);
    return id;
  }

  Future<void> _acceptFile(String id) => _claimIncoming(id, (transfer) async {
    transfer.state = 'transferring';
    transfer.chunks = BytesBuilder(copy: false);
    _transfer(transfer);
    _transferDeadline(transfer);
    try {
      await _send({'kind': 'file-accept', 'id': id});
    } on Object {
      _finish(transfer, 'failed');
      rethrow;
    }
  });

  Future<void> _rejectFile(String id) async {
    final transfer = _inbound[id];
    if (transfer == null || transfer.state != 'offered') return;
    try {
      await _send({'kind': 'file-reject', 'id': id});
    } finally {
      _finish(transfer, 'rejected');
    }
  }

  Future<void> _cancelFile(String id) async {
    final transfer = [
      _inbound[id],
      _outbound[id],
    ].where((t) => _active.contains(t?.state)).firstOrNull;
    if (transfer == null) return;
    // Stop streaming before waiting for the serialized control frame.
    _finish(transfer, 'cancelled');
    await _send({'kind': 'file-cancel', 'id': id});
  }
}
