part of 'web_chat_bridge.dart';

extension WebChatFiles on WebChatBridge {
  Future<void> offerBytes(
    String id,
    String name,
    Uint8List bytes, {
    bool voice = false,
  }) async {
    final room = rooms[id];
    if (room == null || room.closing) return;
    final source = _reserveSource(room, name, bytes, voice: voice);
    await _enqueueSource(source);
  }

  Future<void> offerPlatformFiles(
    String id,
    List<PlatformFile> files, {
    void Function()? onTooLarge,
  }) async {
    final room = rooms[id];
    if (room == null || room.closing) return;
    await _offerAll(
      room,
      files.length,
      (i) async => (
        name: files[i].name,
        source: await webSourceFromPlatformFile(files[i]),
      ),
      onTooLarge,
    );
  }

  Future<void> offerPaths(
    String id,
    List<String> paths, {
    void Function()? onTooLarge,
  }) async {
    final room = rooms[id];
    if (room == null || room.closing) return;
    await _offerAll(
      room,
      paths.length,
      (i) async => (
        name: paths[i].split(RegExp(r'[/\\]')).last,
        source: await webSourceFromPath(paths[i]),
      ),
      onTooLarge,
    );
  }

  // 제안하지 못한 소스(상한 초과, 실패 뒤 남은 것)의 네이티브 권한은 _offerAll이 놓음
  Future<void> offerSources(
    String id,
    List<MobileFileSource> sources, {
    void Function()? onTooLarge,
  }) async {
    final room = rooms[id];
    if (room == null || room.closing) {
      await MobileFileSource.releaseEach(sources);
      return;
    }
    await _offerAll(
      room,
      sources.length,
      (i) async =>
          (name: sources[i].name, source: _MobileWebByteSource(sources[i])),
      onTooLarge,
    );
  }

  Future<void> accept(String id) async {
    final room = _files[id], transfer = store.transfer(id);
    if (room == null ||
        transfer?.state != TransferState.offered ||
        _heldBytes.containsKey(id) ||
        !_accepting.add(id)) {
      return;
    }
    try {
      final useStream = !transfer!.voice && room.streamOffers.contains(id);
      if (!useStream) {
        final held = _heldBytes.values.fold<int>(0, (sum, s) => sum + s);
        if (held + transfer.totalBytes > webPeerMaxFileBytes ||
            _heldBytes.length >= 100) {
          throw const WebPeerProblem('receive-budget');
        }
        _heldBytes[id] = transfer.totalBytes;
        store.updateTransfer(
          id,
          (t) => t.copyWith(state: TransferState.accepted),
        );
        try {
          await room.fileOwners[id]?.session.acceptFile(id);
        } on Object {
          _heldBytes.remove(id);
          _failAccepted(id);
          rethrow;
        }
        return;
      }
      if (_heldBytes.length >= 100) {
        throw const WebPeerProblem('receive-budget');
      }
      final epoch = room.epoch;
      bool wanted() =>
          !room.closing && epoch == room.epoch && store.transfer(id) != null;
      final WebReceiveSink? sink;
      try {
        sink = await openWebReceiveSink(
          transfer.fileName,
          transfer.totalBytes,
          chooseDirectory: chooseDirectory,
          wanted: wanted,
        );
      } on StateError catch (error) {
        if (error.message == 'insufficient-storage') {
          store.updateTransfer(
            id,
            (t) => t.copyWith(
              state: TransferState.failed,
              error: 'insufficient-storage',
            ),
          );
          await room.fileOwners[id]?.session.rejectFile(id);
          throw const WebPeerProblem('receive-budget');
        }
        rethrow;
      }
      // 폴더 선택·용량 확인 중 상대가 취소했거나 끊겼으면 끝난 타일을 수락으로 되살리지 않음
      final offered = store.transfer(id)?.state == TransferState.offered;
      if (sink == null || !wanted() || !offered) {
        await sink?.abort();
        if (wanted() && offered) {
          await room.fileOwners[id]?.session.rejectFile(id);
          store.updateTransfer(
            id,
            (t) => t.copyWith(state: TransferState.cancelled),
          );
        }
        return;
      }
      // 자리가 다 차서 미뤄진 수락은 바이트가 안 흐르니 예약 없음. 시작 뒤 RAM은 스트림 창(4 MiB)이 막음
      final deferred = room.fileOwners[id]?.session.receiveLanesBusy == true;
      final reserve = sink is MemoryBufferReceiveSink
          ? transfer.totalBytes
          : deferred
          ? 0
          : transfer.totalBytes.clamp(0, 4 * 1024 * 1024);
      final held = _heldBytes.values.fold<int>(0, (sum, s) => sum + s);
      if (held + reserve > webPeerMaxFileBytes) {
        await sink.abort();
        throw const WebPeerProblem('receive-budget');
      }
      _heldBytes[id] = reserve;
      store.updateTransfer(
        id,
        (t) => t.copyWith(state: TransferState.accepted),
      );
      try {
        await room.fileOwners[id]?.session.acceptFileStream(
          id,
          sink,
          wanted: wanted,
        );
      } on Object {
        _heldBytes.remove(id);
        await sink.abort();
        _failAccepted(id);
        rethrow;
      }
    } finally {
      _accepting.remove(id);
    }
  }

  // 세션이 수락을 못 받으면(이미 끝난 전송) 수락 표시로 남기지 않음
  void _failAccepted(String id) {
    if (store.transfer(id)?.state == TransferState.accepted) {
      store.updateTransfer(id, (t) => t.copyWith(state: TransferState.failed));
    }
  }

  Future<void> reject(String id) async =>
      _files[id]?.fileOwners[id]?.session.rejectFile(id);
  Future<void> cancel(String id) async =>
      _files[id]?.fileOwners[id]?.session.cancelFile(id);
  Future<void> retry(String id) async {
    final room = _files[id], source = _files[id]?.outgoing[id];
    if (room == null || source == null || source.queued) return;
    room.outgoing.remove(id);
    source.ids.remove(id);
    await _enqueueSource(source, only: room.fileOwners[id]);
  }

  Future<void> discard(FileTransfer transfer) async {
    _heldBytes.remove(transfer.id);
    final room = _files.remove(transfer.id);
    if (room == null) return;
    room.streamOffers.remove(transfer.id);
    await room.fileOwners[transfer.id]?.session.cancelFile(transfer.id);
    room.fileOwners.remove(transfer.id);
    room.fileBytes.remove(transfer.id);
    final source = room.outgoing.remove(transfer.id);
    source?.ids.remove(transfer.id);
    _sourceChanged(source);
    if (transfer.localPath != null) discardWebReceived(transfer.localPath!);
  }
}
