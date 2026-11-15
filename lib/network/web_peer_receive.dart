part of 'web_peer.dart';

final class _Transfer {
  _Transfer({
    required this.id,
    required this.name,
    required this.direction,
    required this.size,
    this.bytes,
    this.origin,
    this.alias,
    this.batch,
    this.streamOffer = false,
    this.source,
    this.onDigest,
  });
  final String id, name, direction;
  final String? origin, alias, batch;
  final int size;
  final bool streamOffer;
  final void Function(String sha256B64)? onDigest;
  String state = 'offered';
  int transferred = 0,
      creditOffset = 0,
      persisted = 0,
      lastCredit = 0,
      queuedSinkBytes = 0;
  Uint8List? bytes;
  BytesBuilder? chunks;
  WebByteSource? source;
  WebReceiveSink? sink;
  bool Function()? wanted;
  DartHashSink? hashSink;
  Completer<void>? creditWaiter;
  Future<void> sinkQueue = Future<void>.value();
  String? localPath, sha256B64;
  Timer? timer;
  bool ended = false, streamMode = false;
  // 보내는 쪽: 상대 수락을 받음(빈 자리를 기다릴 수 있음), 상대가 스트림 조각으로 받겠다고 함,
  // 상대가 수락했지만 자기 자리가 없어 기다린다고 알림(file-queued)
  bool accepted = false, peerStreams = false, peerQueued = false;
  // 받는 쪽: 자리가 다 차서 미뤄 둔 수락
  Future<void> Function(_Transfer transfer)? start;
}

extension _WebPeerReceive on WebPeerSession {
  void _handleData(RTCDataChannelMessage data) {
    if (state == 'closed') return;
    try {
      // DTLS may deliver data while asynchronous fingerprint calculation is still running.
      if (state != 'connected') {
        final size = data.isBinary
            ? data.binary.length
            : utf8.encode(data.text).length;
        if (_pendingData.length >= 64 || _pendingBytes + size > 1024 * 1024) {
          throw const WebPeerProblem('invalid-frame');
        }
        _pendingData.add(data);
        _pendingBytes += size;
        return;
      }
      _receive(data);
    } on Object catch (error) {
      _fail(error);
    }
  }

  void _receive(RTCDataChannelMessage data) {
    if (data.isBinary) {
      final binary = data.binary;
      // 받는 쪽이 취소·실패한 뒤에도 상대가 이미 보낸 조각이 옴: 크기만 막고 지금 받는 파일 것이 아니면 버림
      if (binary.length <= 20 || binary.length > webPeerStreamChunkBytes + 24) {
        throw const WebPeerProblem('invalid-frame');
      }
      // 두 조각 형식 모두 앞 16바이트가 전송 id임
      final id = webPeerParseChunk(Uint8List.sublistView(binary, 0, 21)).id;
      final transfer = _inbound[id];
      if (transfer == null || transfer.state != 'transferring') return;
      if (transfer.sink != null) {
        _receiveStreamBinary(transfer, binary);
        return;
      }
      final chunk = webPeerParseChunk(binary);
      if (chunk.offset != transfer.transferred ||
          transfer.transferred + chunk.bytes.length > transfer.size) {
        throw const WebPeerProblem('invalid-file-data');
      }
      // Plugin event buffers may be reused; retain an owned copy until consented file completion.
      transfer.chunks!.add(Uint8List.fromList(chunk.bytes));
      transfer.transferred += chunk.bytes.length;
      _transfer(transfer);
      _transferDeadline(transfer);
      return;
    }
    final frame = webPeerParseFrame(data.text);
    final id = frame['id'] as String;
    final incoming = _inbound[id];
    final outgoing = _outbound[id];
    switch (frame['kind']) {
      case 'text':
        if (!_remember(id)) return;
        onTextFrame?.call({'id': id, 'text': frame['text']});
        onMessage?.call(frame['text'] as String);
      case 'control':
        if (!_remember(id)) return;
        onControl?.call((frame['control'] as Map).cast<String, dynamic>());
      case 'part':
        _receivePart(frame);
      case 'file-offer':
        if (incoming != null) return;
        if (!_remember(id)) return;
        if (!_queueOffer(frame)) {
          unawaited(
            _send({'kind': 'file-reject', 'id': id}).catchError((Object error) {
              _fail(error);
            }),
          );
        }
      case 'file-cancel':
        for (final transfer in [incoming, outgoing]) {
          if (transfer != null && _active.contains(transfer.state)) {
            _finish(transfer, 'cancelled');
          }
        }
      case 'file-reject':
        if (outgoing != null && outgoing.state == 'offered') {
          _finish(outgoing, 'rejected');
        }
      case 'file-accept':
        _claimOutgoing(id, frame['stream'] == true);
      case 'file-queued':
        // 상대 자리를 채울 우리 전송이 하나도 없으면 줄 세울 이유가 없음: 수락 없이 보낸 알림은 무시함
        if (outgoing != null &&
            outgoing.state == 'offered' &&
            !outgoing.peerQueued &&
            _peerBusy) {
          outgoing.peerQueued = true;
          _transfer(outgoing);
        }
      case 'file-credit':
        if (outgoing == null ||
            outgoing.state != 'transferring' ||
            !outgoing.streamMode) {
          return;
        }
        final nextCredit = frame['offset'] as int;
        if (nextCredit > outgoing.creditOffset) {
          outgoing.creditOffset = nextCredit;
          final waiter = outgoing.creditWaiter;
          outgoing.creditWaiter = null;
          if (waiter != null && !waiter.isCompleted) waiter.complete();
        }
      case 'file-end':
        if (incoming == null || incoming.state != 'transferring') return;
        if (incoming.transferred != incoming.size) {
          throw const WebPeerProblem('incomplete-file');
        }
        if (incoming.sink != null) {
          _finalizeStreamReceive(incoming);
          return;
        }
        final bytes = incoming.chunks!.takeBytes();
        // The ordered ACK is sent only after all declared bytes have been authenticated and assembled.
        unawaited(
          _send({'kind': 'file-done', 'id': id})
              .then((_) {
                if (incoming.state == 'transferring') {
                  _finish(incoming, 'complete', bytes);
                }
              })
              .catchError((Object error) {
                _fail(error);
              }),
        );
      case 'file-done':
        if (outgoing == null || outgoing.state != 'transferring') return;
        if (!outgoing.ended || outgoing.transferred != outgoing.size) {
          throw const WebPeerProblem('invalid-file-receipt');
        }
        _finish(outgoing, 'complete');
    }
  }

  bool _remember(String id) {
    if (!_seen.add(id)) return false;
    if (_seen.length > 1000) _seen.remove(_seen.first);
    return true;
  }
}
