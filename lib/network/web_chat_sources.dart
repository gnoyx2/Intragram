part of 'web_chat_bridge.dart';

final class _MobileWebByteSource implements WebByteSource {
  _MobileWebByteSource(this._source);
  final MobileFileSource _source;
  @override
  int get length => _source.size;
  @override
  Stream<Uint8List> openRead() => rechunkByteStream(_source.openRead());
  @override
  Future<void> dispose() => _source.release();
}

class _WebFileSource {
  _WebFileSource.memory(
    this.room,
    this.name,
    Uint8List bytes,
    this.voice,
    this.origin,
    this.alias,
  ) : bytes = Uint8List.fromList(bytes),
      stream = null;

  _WebFileSource.stream(
    this.room,
    this.name,
    WebByteSource this.stream,
    this.origin,
    this.alias,
  ) : bytes = null,
      voice = false;

  final _WebRoom room;
  final String name, origin, alias;
  final Uint8List? bytes;
  final WebByteSource? stream;
  final bool voice;
  final ids = <String>{};
  bool queued = true;
  final reservedAt = DateTime.now();
  String? upstreamId, batchId, batchLabel;
  int get ramLength => bytes?.length ?? 0;
}

extension _WebChatSources on WebChatBridge {
  // v7 방처럼 수신자별로 줄 섬: 답하지 않는 멤버의 제안이 다른 멤버에게 갈 파일을 막지 않음
  Future<void> _enqueueSource(
    _WebFileSource source, {
    _WebChatPeer? except,
    _WebChatPeer? only,
  }) async {
    final room = source.room, epoch = source.room.epoch;
    source.queued = true;
    Object? error;
    var offered = false;
    try {
      await Future.wait([
        for (final peer in room.connected.where(
          (peer) => peer != except && (only == null || peer == only),
        ))
          peer.fileQueue = peer.fileQueue
              .then((_) => _offerTo(peer, source, epoch))
              .then(
                (ok) => offered |= ok,
                onError: (Object caught) => error = caught,
              ),
      ]);
      if (!offered) throw error ?? const WebPeerProblem('not-connected');
    } finally {
      source.queued = false;
      _sourceChanged(source);
    }
  }

  Future<bool> _offerTo(
    _WebChatPeer peer,
    _WebFileSource source,
    int epoch,
  ) async {
    final room = source.room;
    bool open() =>
        !room.closing &&
        !_disposed &&
        epoch == room.epoch &&
        peer.session.state == 'connected';
    Iterable<String> pending() => room.fileOwners.entries
        .where(
          (owner) =>
              owner.value == peer &&
              store.transfer(owner.key)?.direction ==
                  TransferDirection.outgoing &&
              _activeTransfer(owner.key),
        )
        .map((owner) => owner.key);
    // 동시 전송을 아는 상대에겐 제안 상한까지 바로 걺. 모르는 상대에겐 앞 파일이 끝날 때까지 기다림
    // (같은 묶음끼리는 안 기다림: 상대가 한꺼번에 보고 전부 수락할 수 있음)
    bool wait() => peer.session.peerLanes > 1
        ? pending().length > webPeerMaxWaitingOffers
        : pending().any(
            (id) =>
                source.batchId == null ||
                room.outgoing[id]?.batchId != source.batchId,
          );
    while (open() && wait()) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!open()) return false;
    final transferId = webPeerNewId();
    source.ids.add(transferId);
    room.outgoing[transferId] = source;
    try {
      if (source.stream != null) {
        await peer.session.offerStream(
          source.name,
          source.stream!,
          id: transferId,
          origin: room.hosting ? source.origin : null,
          alias: room.hosting ? source.alias : null,
          batch: peer.batchOffers ? source.batchId : null,
          onDigest: (d) => peer.proof.expectFileDigest(transferId, d),
        );
      } else {
        await peer.session.offerPreparedBytes(
          source.name,
          source.bytes!,
          id: transferId,
          origin: room.hosting ? source.origin : null,
          alias: room.hosting ? source.alias : null,
          batch: peer.batchOffers ? source.batchId : null,
        );
        peer.proof.expectFile(transferId, source.bytes!);
      }
      if (source.upstreamId != null) {
        room.forwarded.putIfAbsent(source.upstreamId!, () => {})[peer] =
            transferId;
      }
      final transfer = store.transfer(transferId);
      if (transfer != null && source.voice) {
        store.upsertTransfer(_fileWithVoice(transfer));
      }
      return true;
    } on Object {
      if (store.transfer(transferId) == null) {
        source.ids.remove(transferId);
        room.outgoing.remove(transferId);
      }
      rethrow;
    }
  }
}
