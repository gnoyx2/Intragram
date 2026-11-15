part of 'web_peer.dart';

const _streamWindowBytes = 4 * 1024 * 1024;
const _streamCreditStepBytes = 1024 * 1024;

extension _WebPeerStreaming on WebPeerSession {
  Future<String> _offerStream(
    String name,
    WebByteSource source, {
    String? id,
    String? origin,
    String? alias,
    String? batch,
    void Function(String sha256B64)? onDigest,
  }) async {
    _checkOutgoingRoom(batch);
    id ??= webPeerNewId();
    final frame = {
      'kind': 'file-offer',
      'id': id,
      'name': name,
      'size': source.length,
      'stream': true,
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
      size: source.length,
      origin: origin,
      alias: alias,
      batch: batch,
      streamOffer: true,
      source: source,
      onDigest: onDigest,
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

  Future<void> _acceptFileStream(
    String id,
    WebReceiveSink sink, {
    bool Function()? wanted,
  }) => _claimIncoming(id, sink: sink, (transfer) async {
    transfer.state = 'transferring';
    transfer.sink = sink;
    transfer.wanted = wanted;
    transfer.hashSink = const DartSha256().newHashSink();
    transfer.streamMode = transfer.streamOffer;
    transfer.lastCredit = _streamWindowBytes;
    _transfer(transfer);
    _transferDeadline(transfer);
    try {
      await _send({
        'kind': 'file-accept',
        'id': id,
        if (transfer.streamMode) 'stream': true,
      });
    } on Object {
      _finish(transfer, 'failed');
      rethrow;
    }
  });

  Future<void> _streamSource(_Transfer transfer) async {
    try {
      final source = transfer.source;
      if (source == null) throw const WebPeerProblem('invalid-file-data');
      final maxChunk = transfer.streamMode
          ? webPeerStreamChunkBytes
          : webPeerChunkBytes;
      final hash = const DartSha256().newHashSink();
      await for (final raw in rechunkByteStream(
        source.openRead(),
        maxChunkBytes: maxChunk,
      )) {
        if (transfer.state != 'transferring') return;
        if (transfer.transferred + raw.length > transfer.size) {
          throw const WebPeerProblem('invalid-file-data');
        }
        while (transfer.streamMode &&
            transfer.transferred + raw.length > transfer.creditOffset) {
          if (transfer.state != 'transferring') return;
          final waiter = transfer.creditWaiter ??= Completer<void>();
          await waiter.future.timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw const WebPeerProblem('transfer-timeout'),
          );
        }
        await _backpressure();
        if (transfer.state != 'transferring') return;
        hash.add(raw);
        final packet = transfer.streamMode
            ? webPeerMakeStreamChunk(transfer.id, transfer.transferred, raw)
            : webPeerMakeChunk(transfer.id, transfer.transferred, raw);
        await _sendRaw(RTCDataChannelMessage.fromBinary(packet));
        if (transfer.state != 'transferring') return;
        transfer.transferred += raw.length;
        _transfer(transfer);
      }
      if (transfer.state != 'transferring') return;
      if (transfer.transferred != transfer.size) {
        throw const WebPeerProblem('incomplete-file');
      }
      hash.close();
      final digest = base64Encode(hash.hashSync().bytes);
      transfer.sha256B64 = digest;
      transfer.onDigest?.call(digest);
      await _backpressure();
      if (transfer.state != 'transferring') return;
      transfer.ended = true;
      await _send({'kind': 'file-end', 'id': transfer.id});
      _awaitCommit(transfer);
    } on Object catch (error) {
      _abandon(transfer, error);
    }
  }

  void _receiveStreamBinary(_Transfer transfer, Uint8List binary) {
    final chunk = transfer.streamMode
        ? webPeerParseStreamChunk(binary)
        : webPeerParseChunk(binary);
    if (transfer.id != chunk.id || transfer.state != 'transferring') return;
    if (chunk.offset != transfer.transferred ||
        transfer.transferred + chunk.bytes.length > transfer.size ||
        transfer.streamMode &&
            transfer.queuedSinkBytes + chunk.bytes.length >
                _streamWindowBytes + webPeerStreamChunkBytes) {
      throw const WebPeerProblem('invalid-file-data');
    }
    final owned = Uint8List.fromList(chunk.bytes);
    transfer.transferred += owned.length;
    transfer.queuedSinkBytes += owned.length;
    transfer.hashSink!.add(owned);
    _transfer(transfer);
    _transferDeadline(transfer);
    final sinkRef = transfer.sink!;
    transfer.sinkQueue = transfer.sinkQueue
        .then((_) async {
          if (transfer.state != 'transferring' || transfer.sink != sinkRef) {
            owned.fillRange(0, owned.length, 0);
            return;
          }
          await sinkRef.write(owned);
          final written = owned.length;
          owned.fillRange(0, owned.length, 0);
          transfer.queuedSinkBytes -= written;
          transfer.persisted += written;
          if (transfer.streamMode &&
              transfer.persisted < transfer.size &&
              transfer.persisted + _streamWindowBytes - transfer.lastCredit >=
                  _streamCreditStepBytes) {
            transfer.lastCredit = transfer.persisted + _streamWindowBytes;
            await _send({
              'kind': 'file-credit',
              'id': transfer.id,
              'offset': transfer.lastCredit,
            });
          }
        })
        .catchError((Object error) {
          _abandon(transfer, error);
        });
  }

  void _finalizeStreamReceive(_Transfer incoming) {
    // 바이트는 다 받음: 커밋(flush·이름 바꾸기)은 로컬 작업이라 받는 쪽 기한을 멈춤. 기다림은 보내는 쪽 기한이 맡음
    incoming.timer?.cancel();
    incoming.timer = null;
    unawaited(
      incoming.sinkQueue
          .then((_) async {
            if (incoming.state != 'transferring' || incoming.sink == null) {
              return;
            }
            final hash = incoming.hashSink!;
            incoming.hashSink = null;
            hash.close();
            final digest = base64Encode(hash.hashSync().bytes);
            final sink = incoming.sink!;
            incoming.sink = null;
            // 커밋 중 취소·실패되면 파일을 남기지 않음 (취소된 타일 뒤에 파일이 남으면 안 됨)
            final String? path;
            try {
              path = await sink.commit(
                wanted: () =>
                    incoming.state == 'transferring' &&
                    (incoming.wanted?.call() ?? true),
              );
            } on Object catch (error) {
              // 디스크 꽉 참·폴더 분리 같은 저장 실패는 쓰기 실패처럼 이 파일만 끝냄
              _abandon(incoming, error);
              return;
            }
            if (path != null && incoming.state == 'transferring') {
              try {
                await _send({'kind': 'file-done', 'id': incoming.id});
              } on Object {
                if (_active.contains(incoming.state)) {
                  _finish(incoming, 'failed');
                }
                await discardCommittedWebFile(path);
                rethrow;
              }
            }
            if (path != null && incoming.state == 'transferring') {
              _finish(incoming, 'complete', null, path, digest);
              return;
            }
            // 커밋하는 사이나 file-done을 보내는 사이에 취소·끊김: 방금 만든 파일을 지움
            if (path != null) await discardCommittedWebFile(path);
            if (incoming.state == 'transferring') {
              unawaited(
                _send({
                  'kind': 'file-cancel',
                  'id': incoming.id,
                }).catchError((Object _) {}),
              );
              _finish(incoming, 'cancelled');
            }
          })
          .catchError((Object error) {
            if (_active.contains(incoming.state)) {
              _finish(incoming, 'failed');
            }
            _fail(error);
          }),
    );
  }
}
