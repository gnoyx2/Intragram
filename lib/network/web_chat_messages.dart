part of 'web_chat_bridge.dart';

extension WebChatMessages on WebChatBridge {
  Future<void> sendText(
    String conversationId,
    String text, {
    String? replyToId,
  }) async {
    final room = rooms[conversationId];
    if (room == null || room.closing || text.trim().isEmpty) return;
    final mode = store.largeMessageMode;
    final textBytes = utf8.encode(text).length;
    if (mode == LargeMessageMode.spillToFile &&
        textBytes > kSpillThresholdBytes) {
      await offerBytes(
        conversationId,
        'message.txt',
        Uint8List.fromList(utf8.encode(text)),
      );
      return;
    }
    if ((mode == LargeMessageMode.inline &&
            textBytes > kMaxInlineMessageBytes) ||
        textBytes > kFrameCeilingBytes) {
      store.addMessage(
        EphemeralMessage(
          id: webPeerNewId(),
          conversationId: conversationId,
          direction: MessageDirection.outgoing,
          kind: MessageKind.text,
          senderAlias: identity.alias,
          createdAt: DateTime.now(),
          text: text,
          replyToId: replyToId,
          delivery: DeliveryState.failed,
        ),
      );
      return;
    }
    final id = webPeerNewId(),
        ttl = store.conversation(conversationId)?.outgoingTtlSeconds ?? 0;
    final candidate = store.messageById(replyToId ?? '');
    final reply = candidate?.conversationId == conversationId
        ? candidate
        : null;
    final safeReply = reply?.id;
    store.addMessage(
      EphemeralMessage(
        id: id,
        conversationId: conversationId,
        direction: MessageDirection.outgoing,
        kind: MessageKind.text,
        senderAlias: identity.alias,
        createdAt: DateTime.now(),
        text: text,
        replyToId: safeReply,
        ttlSeconds: ttl,
        delivery: DeliveryState.sending,
      ),
    );
    room.origins[id] = room.selfId;
    final epoch = room.epoch;
    final signed = await room.authored(id, text, ttl, safeReply);
    if (room.closing || room.epoch != epoch || store.messageById(id) == null) {
      return;
    }
    var sent = false;
    for (final peer in room.connected) {
      try {
        if (signed != null && peer.nativeRoom) {
          await peer.session.sendControl({
            'k': 'native-room',
            'host': room.authenticatedHost,
            'frame': signed,
            'origin': room.selfId,
            'alias': identity.alias,
          });
        } else {
          await peer.session.sendText(
            text,
            id: id,
            maxBytes: kFrameCeilingBytes,
          );
        }
        sent = true;
        room.sendTo(peer, {
          'k': 'meta',
          'id': id,
          'ttl': ttl,
          if (replyToId != null && replyToId.length == 32) 'replyTo': replyToId,
          if (reply?.text != null)
            'quote': reply!.text!.substring(
              0,
              reply.text!.length.clamp(0, 500),
            ),
        });
      } on Object {
        /* Another live room member may still receive it. */
      }
    }
    store.setDelivery(id, sent ? DeliveryState.sent : DeliveryState.failed);
    if (room.hosting) room.nativeRoster();
  }

  void sendControl(String roomId, Map<String, dynamic> control) {
    final room = rooms[roomId];
    room?.broadcast(control);
    if (room?.hosting == true) {
      room!.routeFileControl(null, control, room.selfId);
    }
    if (control['k'] == 'burn') {
      room?.signedMessages.remove(control['id']);
      room?.metas.remove(control['id']);
    }
  }

  Future<void> markRead(String roomId) async {
    final ids = store.markIncomingRead(roomId);
    store.clearUnread(roomId);
    for (final id in ids) {
      sendControl(roomId, {'k': 'read', 'id': id});
    }
  }

  void verify(String roomId, {String? peerId, required String? sas}) {
    final room = rooms[roomId];
    if (room == null) return;
    final peer = peerId == null || !room.hosting && peerId == room.hostId
        ? room.connected.firstOrNull
        : room.peers[peerId];
    if (peer == null || peer.session.verificationCode != sas) return;
    if (peerId == null) {
      store.setLocalVerified(roomId);
    } else {
      store.setRoomMemberLocalVerified(roomId, peerId);
    }
    room.sendTo(peer, {'k': 'verify', 'sas': sas});
  }
}

extension _WebChatInboundMessages on _WebRoom {
  void receiveText(
    _WebChatPeer peer,
    Map<String, dynamic> frame, {
    String? origin,
    String? alias,
    bool relay = true,
    bool integrityChecked = false,
  }) {
    if (closing || bridge._disposed || store.conversation(id) == null) return;
    // Like native v7, inline/spill receivers drop text above 1 MiB.
    if (store.largeMessageMode != LargeMessageMode.unlimited &&
        utf8.encode(frame['text'] as String).length > kMaxInlineMessageBytes) {
      return;
    }
    void again() => receiveText(
      peer,
      frame,
      origin: origin,
      alias: alias,
      relay: relay,
      integrityChecked: integrityChecked,
    );
    if (holdUnbound(peer, again) || deferUntilIdentity(peer, again)) return;
    final messageId = frame['id'] as String;
    if (origins.containsKey(messageId) ||
        store.messageById(messageId) != null ||
        store.transfer(messageId) != null) {
      return;
    }
    final author = origin ?? (hosting ? peer.id : hostId ?? peer.id);
    final authorId = hosting
        ? peer.proof.peerIdentity?.peerId
        : authorIds[author];
    if (!integrityChecked &&
        store.conversation(id)?.isRoom == true &&
        authorId != null &&
        store.roomIntegrity.scope(id) != null) {
      final epoch = this.epoch;
      unawaited(
        store.roomIntegrity.observe(id, frame, actorId: authorId).then((ok) {
          if (ok && epoch == this.epoch) {
            receiveText(
              peer,
              frame,
              origin: origin,
              alias: alias,
              relay: relay,
              integrityChecked: true,
            );
          }
        }),
      );
      return;
    }
    origins[messageId] = author;
    final candidate = metas.remove(messageId);
    final meta = candidate?['_origin'] == author ? candidate : null;
    final quoted = store.messageById(meta?['replyTo'] as String? ?? '');
    store.addMessage(
      EphemeralMessage(
        id: messageId,
        conversationId: id,
        direction: MessageDirection.incoming,
        kind: MessageKind.text,
        senderAlias: alias ?? peer.alias,
        senderPeerId: author,
        createdAt: DateTime.now(),
        text: frame['text'] as String,
        replyToId: quoted?.conversationId == id ? quoted?.id : null,
        ttlSeconds: meta?['ttl'] as int? ?? 0,
        delivery: DeliveryState.delivered,
      ),
    );
    store.bumpUnread(id);
    store.setPeerTyping(id, typing: false);
    sendTo(peer, {'k': 'receipt', 'id': messageId});
    if (hosting && relay) {
      broadcast({
        'k': 'room-msg',
        'id': messageId,
        'origin': author,
        'alias': peer.alias,
        'text': frame['text'],
      }, peer);
    }
  }
}
