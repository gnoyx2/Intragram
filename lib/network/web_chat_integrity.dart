part of 'web_chat_bridge.dart';

const _peerPlatforms = {
  'iOS',
  'iPadOS',
  'macOS',
  'Android',
  'Windows',
  'Linux',
  'Web',
};

extension _WebChatRoomIntegrity on _WebRoom {
  String? get authenticatedHost => hosting
      ? identity.peerId
      : connected.firstOrNull?.proof.peerIdentity?.peerId;

  void nativeRoster() {
    if (!hosting || closing || !connected.any((p) => p.nativeRoom)) return;
    final book = store.roomIntegrity;
    book.ensureRoom(id, host: identity.peerId);
    final authors = <String>{
      identity.peerId,
      for (final p in connected)
        if (p.proof.peerIdentity != null) p.proof.peerIdentity!.peerId,
    }.toList();
    book.setMembers(id, authors);
    final frame = {
      ...InnerFrame.roomState(count: authors.length, peers: authors),
      ...book.checkpoint(id),
      'origins': {
        selfId: identity.peerId,
        for (final p in connected)
          if (p.proof.peerIdentity != null) p.id: p.proof.peerIdentity!.peerId,
      },
    };
    for (final peer in connected.where((p) => p.nativeRoom)) {
      sendTo(peer, {
        'k': 'native-room',
        'host': identity.peerId,
        'frame': frame,
      });
    }
  }

  Future<Map<String, dynamic>?> authored(
    String messageId,
    String text,
    int ttl,
    String? reply,
  ) async {
    if (store.conversation(id)?.isRoom != true ||
        authenticatedHost == null ||
        store.roomIntegrity.scope(id) == null) {
      return null;
    }
    return store.roomIntegrity.sign(
      id,
      identity,
      InnerFrame.message(
        id: messageId,
        text: text,
        ttlSeconds: ttl,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        replyToId: reply,
      ),
    );
  }

  Future<void> receiveNative(_WebChatPeer peer, Map<String, dynamic> control) {
    if (peer.queuedNative >= 32) return Future<void>.value();
    final epoch = this.epoch;
    peer.queuedNative++;
    final operation = peer.nativeQueue.then((_) async {
      if (epoch == this.epoch) await _receiveNative(peer, control, epoch);
    });
    peer.nativeQueue = operation.catchError((Object _) {});
    return operation.whenComplete(() => peer.queuedNative--);
  }

  Future<void> _receiveNative(
    _WebChatPeer peer,
    Map<String, dynamic> control,
    int epoch,
  ) async {
    if (closing || bridge._disposed) return;
    final frame = (control['frame'] as Map).cast<String, dynamic>();
    if (frame['k'] == 'capabilities') {
      peer.nativeRoom = true;
      peer.batchOffers = frame['batch'] == true;
      peer.session.peerLanes = frame['lanes'] as int? ?? 1;
      // 상대가 알린 기기 종류 (앱이 WebRTC로 붙어도 브라우저로 표시하지 않음). 모르는 값은 버림
      if (_peerPlatforms.contains(frame['platform'])) {
        peer.platform = frame['platform'] as String;
        final slot = hosting ? peer.id : hostId ?? peer.id;
        store.updateConversation(id, (c) {
          final member = c.members[slot];
          if (!c.isRoom) return c.copyWith(peerPlatform: peer.platform);
          if (member == null) return c;
          return c.copyWith(
            members: {
              ...c.members,
              slot: member.copyWith(platform: peer.platform),
            },
          );
        });
      }
      if (hosting) nativeRoster();
      return;
    }
    final remote = peer.proof.peerIdentity;
    if (remote == null) {
      if (peer.pendingNative.length < 16) peer.pendingNative.add(control);
      return;
    }
    final host = authenticatedHost;
    if (control['host'] != host) {
      store.roomIntegrity.conflict(id);
      return;
    }
    final book = store.roomIntegrity;
    if (frame['k'] == 'room_state') {
      if (hosting) return;
      final authors = (frame['peers'] as List).cast<String>();
      if (!authors.contains(identity.peerId) ||
          !authors.contains(remote.peerId)) {
        return;
      }
      book.join(
        id,
        frame['roomIntegrityId'] as String,
        authors,
        host: remote.peerId,
      );
      if (book.observeCheckpoint(id, frame, observerId: remote.peerId)) {
        authorIds = (frame['origins'] as Map).cast<String, String>();
      }
      return;
    }
    if (frame['k'] != 'msg') return;
    final origin = hosting
        ? peer.id
        : control['origin'] as String? ?? hostId ?? peer.id;
    final author = hosting ? remote.peerId : frame['authorPeerId'] as String;
    if (!hosting && (authorIds[origin] != author || origin == selfId)) return;
    if (hosting) {
      book.ensureRoom(id, host: identity.peerId);
      book.setMembers(id, [
        identity.peerId,
        for (final p in connected)
          if (p.proof.peerIdentity != null) p.proof.peerIdentity!.peerId,
      ]);
    }
    final accepted = await book.observe(id, frame, actorId: author);
    if (!accepted || closing || bridge._disposed || epoch != this.epoch) return;
    final messageId = frame['id'] as String;
    if (store.messageById(messageId) != null) return;
    signedMessages.add(messageId);
    metas[messageId] = {
      'ttl': frame['ttl'],
      'replyTo': frame['re'],
      '_origin': origin,
    };
    receiveText(
      peer,
      {'id': messageId, 'text': frame['text']},
      origin: origin,
      alias: hosting ? peer.alias : control['alias'] as String? ?? peer.alias,
      relay: false,
      integrityChecked: true,
    );
    if (hosting) {
      for (final target in connected.where((p) => p != peer)) {
        if (target.nativeRoom) {
          sendTo(target, {
            'k': 'native-room',
            'host': host,
            'frame': frame,
            'origin': origin,
            'alias': peer.alias,
          });
        } else {
          sendTo(target, {
            'k': 'room-msg',
            'id': messageId,
            'origin': origin,
            'alias': peer.alias,
            'text': frame['text'],
          });
          sendTo(target, {
            'k': 'room-control',
            'origin': origin,
            'control': {
              'k': 'meta',
              'id': messageId,
              'ttl': frame['ttl'],
              if (frame['re'] != null) 'replyTo': frame['re'],
            },
          });
        }
      }
      nativeRoster();
    }
  }
}
