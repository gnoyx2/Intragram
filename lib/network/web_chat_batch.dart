part of 'web_chat_bridge.dart';

typedef _PickedFile = ({String name, WebByteSource source});

extension WebChatBatch on WebChatBridge {
  // 여러 파일은 32개씩 한 묶음으로 한꺼번에 제안해 받는 쪽이 전부 수락·거절할 수 있음.
  // 묶음을 모르는 상대(보조 HTML 클라이언트)가 있으면 예전처럼 하나씩 줄 섬.
  // 상한(64 GiB)을 넘는 파일은 빼고 제안을 시작하기 전에 onTooLarge로 알림. 못 연 파일도 나머지를 막지 않고
  // 다 보낸 뒤 그 오류를 던짐
  Future<void> _offerAll(
    _WebRoom room,
    int count,
    Future<_PickedFile> Function(int index) open,
    void Function()? onTooLarge,
  ) async {
    final (:files, :refused, :failure) = await _openAll(count, open);
    var next = 0;
    try {
      if (refused > 0) onTooLarge?.call();
      final batch =
          files.length > 1 &&
          room.connected.isNotEmpty &&
          room.connected.every((peer) => peer.batchOffers);
      for (
        var first = 0;
        first < files.length;
        first += webPeerMaxWaitingOffers
      ) {
        final batchId = batch ? webPeerNewId() : null;
        final queued = <Future<void>>[];
        try {
          for (
            var i = first;
            i < files.length && i < first + webPeerMaxWaitingOffers;
            i++
          ) {
            next = i + 1;
            final source = _reserveStreamSource(
              room,
              files[i].name,
              files[i].source,
            );
            if (batchId == null) {
              await _enqueueSource(source);
              continue;
            }
            queued.add(
              _enqueueSource(
                source
                  ..batchId = batchId
                  ..batchLabel = '${i + 1} / ${files.length}',
              ),
            );
          }
        } on Object {
          await Future.wait(queued.map((f) => f.catchError((Object _) {})));
          rethrow;
        }
        await Future.wait(queued);
      }
    } on Object {
      // 원본으로 잡기 전의 파일은 여기서 놓음 (_reserveStreamSource는 실패하면 그 파일을 스스로 놓음)
      for (final file in files.skip(next)) {
        unawaited(file.source.dispose().catchError((Object _) {}));
      }
      rethrow;
    }
    if (failure != null) Error.throwWithStackTrace(failure.$1, failure.$2);
  }

  // 모두 열어 봄: 상한을 넘는 파일은 바로 놓고, 못 연 파일은 첫 오류만 기억함
  Future<
    ({List<_PickedFile> files, int refused, (Object, StackTrace)? failure})
  >
  _openAll(int count, Future<_PickedFile> Function(int index) open) async {
    final files = <_PickedFile>[];
    var refused = 0;
    (Object, StackTrace)? failure;
    for (var i = 0; i < count; i++) {
      try {
        final file = await open(i);
        if (file.source.length <= webPeerMaxStreamFileBytes) {
          files.add(file);
        } else {
          refused++;
          unawaited(file.source.dispose().catchError((Object _) {}));
        }
      } on Object catch (error, trace) {
        failure ??= (error, trace);
      }
    }
    return (files: files, refused: refused, failure: failure);
  }

  Future<void> acceptBatch(String id, String batchId) async {
    for (final t in _offeredInBatch(id, batchId)) {
      await accept(t.id);
    }
  }

  Future<void> rejectBatch(String id, String batchId) async {
    for (final t in _offeredInBatch(id, batchId)) {
      await reject(t.id);
    }
  }

  List<FileTransfer> _offeredInBatch(String id, String batchId) => store
      .transfersInBatch(id, batchId)
      .where(
        (t) =>
            t.direction == TransferDirection.incoming &&
            t.state == TransferState.offered,
      )
      .toList();
}

extension _WebRelayBatch on _WebRoom {
  // 멤버가 묶음으로 보낸 파일은 중계도 한 묶음으로 내보냄: 다른 멤버도 v7 방처럼 전부 수락·거절할 수 있음
  String? relayBatch(_WebChatPeer sender, String? upstream) => upstream == null
      ? null
      : relayBatches.putIfAbsent('${sender.id}-$upstream', webPeerNewId);
}
