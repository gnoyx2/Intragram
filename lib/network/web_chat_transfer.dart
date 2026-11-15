part of 'web_chat_bridge.dart';

extension _WebChatTransferEvents on _WebRoom {
  void transferChanged(_WebChatPeer peer, WebPeerTransfer transfer) {
    if (closing || bridge._disposed || store.conversation(id) == null) return;
    void again() => transferChanged(peer, transfer);
    if (deferUntilIdentity(peer, again, transfer.bytes?.length ?? 0)) return;
    final existing = store.transfer(transfer.id),
        owner = fileOwners[transfer.id],
        incoming = transfer.direction == 'receive';
    final origin = incoming
        ? hosting
              ? peer.id
              : transfer.origin ?? hostId ?? peer.id
        : outgoing[transfer.id]?.origin ?? selfId;
    if (existing == null && origins.containsKey(transfer.id) ||
        store.messageById(transfer.id) != null && existing == null ||
        existing != null && existing.conversationId != id ||
        // 줄 세웠다던 상대가 끝내 수락하지 않아 '답 없는 제안'으로 되돌아온 내 제안만 다시 offered가 됨
        transfer.state == 'offered' &&
            existing != null &&
            (incoming || existing.state != TransferState.accepted) ||
        owner != null && owner != peer ||
        incoming &&
            !hosting &&
            transfer.origin != null &&
            (!members.containsKey(origin) || origin == selfId)) {
      unawaited(peer.session.rejectFile(transfer.id));
      return;
    }
    fileOwners[transfer.id] = peer;
    bridge._files[transfer.id] = this;
    if (incoming && transfer.stream && transfer.state == 'offered') {
      streamOffers.add(transfer.id);
    }
    if (incoming &&
        ['rejected', 'cancelled', 'failed'].contains(transfer.state)) {
      bridge._heldBytes.remove(transfer.id);
      streamOffers.remove(transfer.id);
    }
    final source = outgoing[transfer.id];
    final voice =
        transfer.size <= kMaxVoiceNoteBytes &&
        (source?.voice ??
            existing?.voice ??
            RegExp(
              r'^voice-.*\.wav$',
              caseSensitive: false,
            ).hasMatch(transfer.name));
    final state = switch (transfer.state) {
      'offered' => TransferState.offered,
      'accepted' => TransferState.accepted,
      'transferring' => TransferState.transferring,
      'complete' => TransferState.complete,
      'rejected' => TransferState.rejected,
      'cancelled' => TransferState.cancelled,
      _ => TransferState.failed,
    };
    store.upsertTransfer(
      FileTransfer(
        id: transfer.id,
        conversationId: id,
        direction: incoming
            ? TransferDirection.incoming
            : TransferDirection.outgoing,
        fileName: transfer.name,
        totalBytes: transfer.size,
        transferredBytes: transfer.transferred,
        state:
            incoming &&
                transfer.bytes != null &&
                transfer.localPath == null &&
                !voice
            ? TransferState.transferring
            : state,
        voice: voice,
        voiceBytes: voice
            ? existing?.voiceBytes ??
                  transfer.bytes ??
                  (source?.bytes == null
                      ? null
                      : Uint8List.fromList(source!.bytes!))
            : null,
        localPath: transfer.localPath ?? existing?.localPath,
        encrypted: true,
        senderPeerId: incoming ? origin : null,
        // 받는 쪽 묶음 id는 보낸 링크별로 갈라서 다른 멤버 제안과 안 섞임
        batchId:
            source?.batchId ??
            (incoming && transfer.batch != null
                ? '${peer.id}-${transfer.batch}'
                : existing?.batchId),
        batchLabel: source?.batchLabel ?? existing?.batchLabel,
      ),
    );
    if (existing == null) {
      origins[transfer.id] = origin;
      if (incoming) store.bumpUnread(id);
      store.addMessage(
        EphemeralMessage(
          id: transfer.id,
          conversationId: id,
          direction: incoming
              ? MessageDirection.incoming
              : MessageDirection.outgoing,
          kind: MessageKind.file,
          senderAlias: incoming
              ? hosting
                    ? peer.alias
                    : transfer.alias ?? peer.alias
              : outgoing[transfer.id]?.alias ?? identity.alias,
          senderPeerId: incoming ? origin : null,
          createdAt: DateTime.now(),
          transferId: transfer.id,
          delivery: DeliveryState.delivered,
        ),
      );
    }
    if (!incoming) bridge._sourceChanged(outgoing[transfer.id]);
    if (incoming &&
        transfer.state == 'complete' &&
        transfer.localPath != null) {
      streamOffers.remove(transfer.id);
      bridge._heldBytes.remove(transfer.id);
      if (hosting && connected.length > 1 && relayingFiles.add(transfer.id)) {
        unawaited(relayFile(peer, transfer, voice: false));
      }
      if (transfer.sha256B64 != null) {
        unawaited(
          peer.proof
              .recordFileDigest(transfer.id, transfer.sha256B64!)
              .catchError((Object _) {}),
        );
      }
    } else if (incoming && transfer.bytes != null) {
      if (hosting && connected.length > 1 && relayingFiles.add(transfer.id)) {
        unawaited(relayFile(peer, transfer, voice: voice));
      }
      unawaited(
        peer.proof
            .recordFile(transfer.id, transfer.bytes!)
            .catchError((Object _) {}),
      );
      if (voice) {
        fileBytes[transfer.id] = transfer.bytes!;
      } else {
        unawaited(_saveTransfer(transfer));
      }
    }
    if (incoming &&
        transfer.state == 'offered' &&
        (voice ||
            store.conversation(id)?.autoAcceptFiles == true &&
                store.conversation(id)?.isRoom != true &&
                store.conversation(id)?.verified == true)) {
      unawaited(bridge.accept(transfer.id).catchError((Object _) {}));
    }
  }

  Future<void> relayFile(
    _WebChatPeer sender,
    WebPeerTransfer transfer, {
    required bool voice,
  }) async {
    final epoch = this.epoch;
    try {
      _WebFileSource? source;
      if (!voice && transfer.localPath != null) {
        final stream = await webSourceFromPath(transfer.localPath!);
        source = bridge._reserveStreamSource(
          this,
          transfer.name,
          stream,
          origin: sender.id,
          alias: sender.alias,
        )..upstreamId = transfer.id;
      } else {
        while (!closing && epoch == this.epoch && source == null) {
          try {
            source = bridge._reserveSource(
              this,
              transfer.name,
              transfer.bytes!,
              voice: voice,
              origin: sender.id,
              alias: sender.alias,
            )..upstreamId = transfer.id;
          } on WebPeerProblem catch (error) {
            if (error.code != 'send-budget') rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
      }
      if (source == null) return;
      source.batchId = relayBatch(sender, transfer.batch);
      await bridge._enqueueSource(source, except: sender);
    } on Object {
      store.updateTransfer(
        transfer.id,
        (t) => t.copyWith(error: 'relay-failed'),
      );
    } finally {
      relayingFiles.remove(transfer.id);
      if (!kIsWeb &&
          !voice &&
          store.transfer(transfer.id)?.state != TransferState.transferring) {
        bridge._heldBytes.remove(transfer.id);
      }
    }
  }

  Future<void> _saveTransfer(WebPeerTransfer transfer) async {
    final epoch = this.epoch;
    bool wanted() =>
        !closing && epoch == this.epoch && store.transfer(transfer.id) != null;
    try {
      final path = await storeWebReceived(
        transfer.name,
        transfer.bytes!,
        chooseDirectory: bridge.chooseDirectory,
        wanted: wanted,
      );
      if (!wanted()) {
        if (path != null) discardWebReceived(path);
        bridge._heldBytes.remove(transfer.id);
        return;
      }
      if ((!kIsWeb || path == null) && !relayingFiles.contains(transfer.id)) {
        bridge._heldBytes.remove(transfer.id);
      }
      store.updateTransfer(
        transfer.id,
        (t) => t.copyWith(
          localPath: path,
          state: path == null
              ? TransferState.cancelled
              : TransferState.complete,
        ),
      );
    } on Object {
      if (!wanted()) return;
      bridge._heldBytes.remove(transfer.id);
      store.updateTransfer(
        transfer.id,
        (t) => t.copyWith(state: TransferState.failed),
      );
    }
  }
}
