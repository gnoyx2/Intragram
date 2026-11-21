part of 'web_chat_bridge.dart';

// 신원 증명 전에 보류 클로저(최대 32개)가 붙잡을 수 있는 프레임 총 바이트 상한 (기본 인라인 상한 1 MiB × 8 = 8 MiB:
// 무제한 모드에서 64 MiB 프레임을 연속으로 보내 최대 2 GiB까지 메모리를 묶어 두는 경로를 막음)
const webChatMaxPendingIdentityBytes = 8 * 1024 * 1024;

const _relayedControls = {
  'meta',
  'read',
  'burn',
  'react',
  'typing',
  'rename',
  'receipt',
};

extension _WebChatInboundControl on _WebRoom {
  void receiveControl(_WebChatPeer peer, Map<String, dynamic> control) {
    if (closing || bridge._disposed || store.conversation(id) == null) return;
    final kind = control['k'];
    if (['identity', 'attestation', 'org-credential'].contains(kind)) {
      unawaited(peer.proof.receive(control).catchError((Object _) {}));
      return;
    }
    final bytes = !peer.bound || peer.proof.peerIdentity == null
        ? utf8.encode(jsonEncode(control)).length
        : 0;
    if (holdUnbound(peer, () => receiveControl(peer, control), bytes)) return;
    if (kind == 'native-room') {
      unawaited(receiveNative(peer, control).catchError((Object _) {}));
      return;
    }
    if (deferUntilIdentity(peer, () => receiveControl(peer, control), bytes)) {
      return;
    }
    if (kind == 'verify') {
      if (control['sas'] == peer.session.verificationCode) {
        if (store.conversation(id)?.isRoom == true) {
          store.setRoomMemberPeerVerified(
            id,
            hosting ? peer.id : hostId ?? peer.id,
          );
        } else {
          store.confirmPeerVerified(id);
        }
      }
      return;
    }
    if (hosting && (kind as String).startsWith('room-')) return;
    if (!hosting && kind == 'room-state') {
      if (hostId != null && hostId != control['host']) return;
      hostId = control['host'] as String;
      selfId = control['self'] as String;
      members = {
        for (final member in control['members'] as List)
          member['id'] as String: member['alias'] as String,
      };
      final group = members.length > 2;
      store.updateConversation(
        id,
        (c) => c.copyWith(
          isRoom: group || c.isRoom,
          localVerified: group ? false : c.localVerified,
          peerVerified: group ? false : c.peerVerified,
          hostAlias: group ? members[hostId] : null,
          hostPeerId: group ? hostId : null,
          memberCount: members.length,
          roomRecipientIds: members.keys.where((key) => key != selfId).toList(),
          members: {
            for (final m in members.entries.where((m) => m.key != selfId))
              m.key: RoomMember(
                alias: m.value,
                platform: m.key == hostId ? peer.platform : 'Browser',
                sas: m.key == hostId ? peer.session.verificationCode : null,
                localVerified:
                    c.members[m.key]?.localVerified == true ||
                    m.key == hostId && !c.isRoom && c.localVerified,
                peerVerified:
                    c.members[m.key]?.peerVerified == true ||
                    m.key == hostId && !c.isRoom && c.peerVerified,
              ),
          },
        ),
      );
      return;
    }
    if (!hosting && kind == 'room-msg') {
      if (!members.containsKey(control['origin']) ||
          control['origin'] == selfId) {
        return;
      }
      receiveText(
        peer,
        {'id': control['id'], 'text': control['text']},
        origin: control['origin'] as String,
        alias: control['alias'] as String,
      );
      return;
    }
    var origin = hosting ? peer.id : hostId ?? peer.id;
    if (!hosting && kind == 'room-control') {
      origin = control['origin'] as String;
      if (!members.containsKey(origin) || origin == selfId) return;
      applyControl(
        peer,
        (control['control'] as Map).cast<String, dynamic>(),
        origin,
      );
      return;
    }
    final valid = applyControl(peer, control, origin);
    if (valid && hosting && _relayedControls.contains(kind)) {
      routeFileControl(peer, control, origin);
      broadcast({
        'k': 'room-control',
        'origin': origin,
        'control': control,
      }, peer);
    }
  }

  // 자동 초대 링크가 기대한 신원을 아직 증명하지 않았으면 프레임을 미룸. 다른 신원이면 버림 (곧 끊김)
  bool holdUnbound(
    _WebChatPeer peer,
    void Function() receive, [
    int bytes = 0,
  ]) {
    if (peer.bound) return false;
    if (peer.proof.peerIdentity == null) {
      deferUntilIdentity(peer, receive, bytes);
    }
    return true;
  }

  bool deferUntilIdentity(
    _WebChatPeer peer,
    void Function() receive, [
    int bytes = 0,
  ]) {
    if (!peer.bound && peer.proof.peerIdentity != null) return true;
    if (peer.proof.peerIdentity != null ||
        peer.expectedPeerId == null &&
            bridge.blockedPeers.isEmpty &&
            store.roomIntegrity.scope(id) == null) {
      return false;
    }
    if (peer.pendingIdentity.length < 32 &&
        peer.pendingIdentityBytes + bytes <= webChatMaxPendingIdentityBytes) {
      peer.pendingIdentity.add(receive);
      peer.pendingIdentityBytes += bytes;
    } else {
      peer.clearPendingIdentity();
      unawaited(peer.session.close());
    }
    return true;
  }

  bool acceptIdentity(_WebChatPeer peer) {
    final remote = peer.proof.peerIdentity;
    if (remote == null) return true;
    if (!peer.bound) {
      // 자동 초대한 그 앱이 아닌 기기가 응답함: 방에 들이지 않고 끊음
      peer.clearPendingIdentity();
      unawaited(peer.session.close());
      return false;
    }
    if (bridge.blockedPeers.contains(remote.peerId)) {
      peer.clearPendingIdentity();
      if (store.conversation(id)?.isRoom != true) {
        store.updateConversation(
          id,
          (c) => c.copyWith(peerId: remote.peerId, blocked: true),
        );
      }
      unawaited(peer.session.close());
      return false;
    }
    if (!peer.opened && peer.session.state == 'connected') admit(peer);
    final pending = peer.pendingIdentity.toList();
    peer.pendingIdentity.clear();
    peer.pendingIdentityBytes = 0;
    for (final receive in pending) {
      receive();
    }
    return true;
  }

  bool applyControl(_WebChatPeer peer, Map<String, dynamic> c, String origin) {
    final messageId = c['id'] as String?,
        m = store.messageById(c['id'] as String? ?? '');
    if (messageId != null && m != null && m.conversationId != id) return false;
    switch (c['k']) {
      case 'rename':
        final alias = c['alias'] as String;
        // 1:1에서 초대받은 쪽은 hostId가 없음: 직접 받은 rename이면 그 링크 이름임 (중계된 room-control 제외)
        if (hosting || origin == (hostId ?? peer.id)) peer.alias = alias;
        if (store.conversation(id)?.isRoom == true) {
          store.renameRoomMember(id, origin, alias);
        } else {
          store.updateConversation(id, (c) => c.copyWith(peerAlias: alias));
        }
        if (hosting) roster();
      case 'typing':
        store.setPeerTyping(id, typing: c['on'] as bool);
      case 'receipt':
        if (m?.isMine == true) {
          store.advanceDelivery(messageId!, DeliveryState.delivered);
        }
      case 'read':
        if (m?.isMine == true) store.applyReadReceipt(messageId!, origin);
      case 'meta':
        if (signedMessages.contains(messageId)) return false;
        if (m == null) {
          if (metas.length < 64) metas[messageId!] = {...c, '_origin': origin};
        } else if (origins[messageId] == origin && !m.isMine) {
          final quote = store.messageById(c['replyTo'] as String? ?? '');
          store.applyWebMetadata(
            messageId!,
            ttl: c['ttl'] as int,
            replyToId: quote?.conversationId == id ? quote?.id : null,
          );
        } else {
          return false;
        }
      case 'burn':
        if (m == null || m.isMine || origins[messageId] != origin) return false;
        unawaited(
          peer.proof
              .recordBurn(messageId!, m.text ?? '')
              .catchError((Object _) {}),
        );
        store.burnMessage(messageId);
        signedMessages.remove(messageId);
      case 'react':
        if (m != null) {
          store.applyReaction(
            messageId!,
            origin,
            c['emoji'] as String,
            on: c['on'] as bool,
          );
        }
    }
    return true;
  }
}
