part of 'web_chat_bridge.dart';

// 송신 원본 예산: RAM 원본 합계 webPeerMaxFileBytes, 원본 100개 (v7엔 없는 WebRTC 쪽 상한).
// 예산이 찼을 때만 이만큼 아무도 수락하지 않은 제안을 취소하고 원본을 풂: 답 없는 멤버가 예산을 붙잡지 않음
// 테스트만 줄여 씀
Duration webChatStaleOfferAge = const Duration(minutes: 2);
const _maxSources = 100;

extension _WebChatBudget on WebChatBridge {
  _WebFileSource _reserveSource(
    _WebRoom room,
    String name,
    Uint8List bytes, {
    required bool voice,
    String? origin,
    String? alias,
  }) {
    if (bytes.length > webPeerMaxFileBytes ||
        voice && bytes.length > kMaxVoiceNoteBytes) {
      throw const WebPeerProblem('invalid-file');
    }
    int used() => _sources.fold(0, (sum, source) => sum + source.ramLength);
    bool full() =>
        used() + bytes.length > webPeerMaxFileBytes ||
        _sources.length >= _maxSources;
    _makeRoom(full);
    if (full()) throw const WebPeerProblem('send-budget');
    final source = _WebFileSource.memory(
      room,
      name,
      bytes,
      voice,
      origin ?? room.selfId,
      alias ?? identity.alias,
    );
    _sources.add(source);
    return source;
  }

  _WebFileSource _reserveStreamSource(
    _WebRoom room,
    String name,
    WebByteSource stream, {
    String? origin,
    String? alias,
  }) {
    if (stream.length > webPeerMaxStreamFileBytes) {
      unawaited(stream.dispose().catchError((Object _) {}));
      throw const WebPeerProblem('invalid-file');
    }
    bool full() => _sources.length >= _maxSources;
    _makeRoom(full);
    if (full()) {
      unawaited(stream.dispose().catchError((Object _) {}));
      throw const WebPeerProblem('send-budget');
    }
    final source = _WebFileSource.stream(
      room,
      name,
      stream,
      origin ?? room.selfId,
      alias ?? identity.alias,
    );
    _sources.add(source);
    return source;
  }

  // 끝난 원본부터 풀고, 그래도 차 있으면 오래 답 없는 제안만 남은 원본을 취소하고 풂 (받는 쪽 타일은 취소로 바뀜)
  void _makeRoom(bool Function() full) {
    for (final source in _sources.toList()) {
      if (!full()) return;
      if (!source.queued && source.ids.every((id) => !_activeTransfer(id))) {
        _releaseSource(source);
      }
    }
    final now = DateTime.now();
    for (final source in _sources.toList()) {
      if (!full()) return;
      final open = source.ids.where(_activeTransfer).toList();
      if (source.queued ||
          now.difference(source.reservedAt) < webChatStaleOfferAge ||
          open.isEmpty ||
          open.any(
            (id) => store.transfer(id)?.state != TransferState.offered,
          )) {
        continue;
      }
      for (final id in open) {
        final session = source.room.fileOwners[id]?.session;
        unawaited(session?.cancelFile(id).catchError((Object _) {}));
      }
      _releaseSource(source);
    }
  }

  bool _activeTransfer(String id) => [
    TransferState.offered,
    TransferState.accepted,
    TransferState.transferring,
  ].contains(store.transfer(id)?.state);

  void _releaseSource(_WebFileSource source) {
    if (!_sources.remove(source)) return;
    for (final id in source.ids) {
      source.room.outgoing.remove(id);
    }
    source.ids.clear();
    final bytes = source.bytes;
    if (bytes != null) bytes.fillRange(0, bytes.length, 0);
    final stream = source.stream;
    if (stream != null) unawaited(stream.dispose().catchError((Object _) {}));
  }

  void _sourceChanged(_WebFileSource? source) {
    if (source != null &&
        !source.queued &&
        (source.ids.isEmpty ||
            source.ids.every(
              (id) => store.transfer(id)?.state == TransferState.complete,
            ))) {
      _releaseSource(source);
    }
  }
}
