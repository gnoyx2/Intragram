part of '../link_registry.dart';

mixin _LinkRegistryFacade on _LinkRegistryState {
  // hello는 핸드셰이크 때 한 번뿐이라 이게 없으면 연결된 상대는 바뀐 이름을 못 봄
  void broadcastRename(String alias) {
    for (final id in _web.activeIds) {
      _web.sendControl(id, {'k': 'rename', 'alias': alias});
    }
    for (final link in <PeerLink>{..._links.values, ..._roomLinks}) {
      if (link.isClosed) continue;
      unawaited(
        link.sendRawInnerOrClose(
          InnerFrame.rename(alias: alias, peerId: identity.peerId),
        ),
      );
    }
  }

  // 확인 안 된 대화에선 무시: 중간자일 수 있어서 그 파일은 탭 없이는 안 떨어짐
  void setAutoAcceptFiles(String conversationId, {required bool enabled}) {
    final conversation = store.conversation(conversationId);
    if (conversation == null || !conversation.verified) return;
    store.setConversationAutoAccept(conversationId, value: enabled);
  }

  // 파일: TransferCoordinator로 넘기는 얇은 위임

  Future<void> offerFile(String conversationId, PlatformFile file) =>
      _web.contains(conversationId)
      ? _web.offerPlatformFiles(conversationId, [file])
      : _transfers.outgoing.offerFile(conversationId, file);

  // onTooLarge: 웹 대화에서 상한(64 GiB)을 넘어 뺀 파일이 있을 때 제안 전에 불림 (v7 대화는 상한 없음)
  Future<void> offerFiles(
    String conversationId,
    List<PlatformFile> files, {
    void Function()? onTooLarge,
  }) => _web.contains(conversationId)
      ? _web.offerPlatformFiles(conversationId, files, onTooLarge: onTooLarge)
      : _transfers.outgoing.offerFiles(conversationId, files);

  Future<void> offerFilesFromPaths(
    String conversationId,
    List<String> paths, {
    void Function()? onTooLarge,
  }) => _web.contains(conversationId)
      ? _web.offerPaths(conversationId, paths, onTooLarge: onTooLarge)
      : _transfers.outgoing.offerFilesFromPaths(conversationId, paths);

  // 모바일 첨부를 디스크 사본 없이 네이티브 스트림 그대로 제안. 소스 자원은 전송이 끝날 때 레지스트리가 놓고,
  // 도중에 실패하면 손도 못 댄 나머지는 여기서 놓음
  Future<void> offerStreamSources(
    String conversationId,
    List<MobileFileSource> sources, {
    void Function()? onTooLarge,
  }) async {
    if (_web.contains(conversationId)) {
      return _web.offerSources(conversationId, sources, onTooLarge: onTooLarge);
    }
    final batchId = sources.length > 1 ? newId() : null;
    var next = 0;
    try {
      for (; next < sources.length; next++) {
        final source = sources[next];
        await _transfers.outgoing.offerStreamSource(
          conversationId: conversationId,
          name: source.name,
          size: source.size,
          openStream: source.openRead,
          batchLabel: sources.length > 1
              ? '${next + 1} / ${sources.length}'
              : null,
          batchId: batchId,
          releaseSource: source.release,
        );
      }
    } on Object {
      // 던진 소스는 offerStreamSource가 맡음. 나머지만 여기서 놓음
      await MobileFileSource.releaseEach(sources.skip(next + 1));
      rethrow;
    }
  }

  // 붙여넣은 이미지·음성 메시지 같은 RAM 바이트를 파일로 제안 (디스크엔 안 씀)
  Future<void> offerInlineBytes(
    String conversationId,
    String name,
    Uint8List bytes, {
    String? mime,
    bool voice = false,
  }) => _web.contains(conversationId)
      ? _web.offerBytes(conversationId, name, bytes, voice: voice)
      : _transfers.outgoing.offerInlineBytes(
          conversationId,
          name,
          bytes,
          mime: mime,
          voice: voice,
        );

  Future<void> acceptTransfer(String transferId) => _web.hasTransfer(transferId)
      ? _web.accept(transferId)
      : _transfers.incoming.accept(transferId);

  Future<void> rejectTransfer(String transferId) => _web.hasTransfer(transferId)
      ? _web.reject(transferId)
      : _transfers.incoming.reject(transferId);

  Future<void> acceptBatch(String conversationId, String batchId) =>
      _web.contains(conversationId)
      ? _web.acceptBatch(conversationId, batchId)
      : _transfers.incoming.acceptBatch(conversationId, batchId);

  Future<void> rejectBatch(String conversationId, String batchId) =>
      _web.contains(conversationId)
      ? _web.rejectBatch(conversationId, batchId)
      : _transfers.incoming.rejectBatch(conversationId, batchId);

  void cancelTransfer(String transferId) {
    if (_web.hasTransfer(transferId)) {
      unawaited(_web.cancel(transferId));
      return;
    }
    switch (store.transfer(transferId)?.direction) {
      case TransferDirection.outgoing:
        _transfers.outgoing.cancelTransfer(transferId);
      case TransferDirection.incoming:
        _transfers.incoming.cancelTransfer(transferId);
      case null:
        break;
    }
  }

  Future<void> retryTransfer(String transferId) async {
    if (_web.hasTransfer(transferId)) return _web.retry(transferId);
    switch (store.transfer(transferId)?.direction) {
      case TransferDirection.outgoing:
        await _transfers.outgoing.retryTransfer(transferId);
      case TransferDirection.incoming:
        await _transfers.incoming.retryTransfer(transferId);
      case null:
        break;
    }
  }

  // 테스트·진단용
  OutgoingFileSource? outgoingSource(String transferId) =>
      _transfers.outgoing.source(transferId);

  // GET /api/download/<id>: 토큰·attempt·선언 크기·상태를 다 확인한 뒤에만 그 수신자 토큰을 씀
  Future<OutgoingDownload?> openDownload({
    required String transferId,
    required String attemptId,
    required String token,
    required int declaredSize,
  }) => _transfers.outgoing.openDownload(
    transferId: transferId,
    attemptId: attemptId,
    token: token,
    declaredSize: declaredSize,
  );

  // attemptId·headerDeclaredSize는 서버가 헤더에서 이미 필수로 검사함
  Future<bool> receiveTransfer({
    required String transferId,
    required String attemptId,
    required String token,
    required Stream<List<int>> body,
    required int headerDeclaredSize,
  }) => _transfers.incoming.receive(
    transferId: transferId,
    attemptId: attemptId,
    token: token,
    body: body,
    headerDeclaredSize: headerDeclaredSize,
  );

  // 테스트가 링크 없이 accept → receive를 직접 몰 때만 씀
  @visibleForTesting
  IncomingTransfers get debugIncoming => _transfers.incoming;

  // debugIncoming의 보내는 쪽판
  @visibleForTesting
  OutgoingTransfers get debugOutgoing => _transfers.outgoing;

  // InMemoryStore.onTransferRemoved에서 불림 (app_providers가 이음)
  Future<void> discardRemovedTransfer(FileTransfer transfer) =>
      _web.hasTransfer(transfer.id)
      ? _web.discard(transfer)
      : _transfers.discardTransfer(transfer);

  // 포털 끔: 웹 게스트 링크를 다 닫음 (토큰 폐기와 짝). 앱 그룹 방은 안 건드림
  Future<void> disconnectWebGuests() async {
    final guestRoomId = _webGuestRoomId;
    if (guestRoomId == null) return;
    final guests = _roomLinks
        .where((link) => link.conversationId == guestRoomId)
        .toList();
    for (final link in guests) {
      await link.close();
    }
  }
}
