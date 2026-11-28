part of 'web_chat_bridge.dart';

extension _WebRoomConnections on _WebRoom {
  _WebChatPeer addPeer(bool dialled) {
    final peer = _WebChatPeer(webPeerNewId(), dialled), epoch = this.epoch;
    bool current() =>
        epoch == this.epoch &&
        !closing &&
        !bridge._disposed &&
        store.conversation(id) != null;
    void state(String value) {
      if (!current()) return;
      if (value == 'connected') {
        final proving = peer.proof.start(
          peer.session.sessionBinding,
          dialled: dialled,
        );
        // 자동 초대 링크는 기대한 신원이 증명된 뒤에야 방에 들임 (acceptIdentity)
        if (peer.bound) {
          admit(peer, proving);
        } else {
          unawaited(proving.catchError((Object _) {}));
        }
      } else if (value == 'closed') {
        peer.settle(false);
        peer.clearPendingIdentity();
        forgetOrganization(peer);
        peer.proof.clear();
        store.setRoomMemberOffline(id, peer.id);
        store.setConversationOnline(id, online: connected.isNotEmpty);
        if (connected.isEmpty) store.clearVerified(id);
        roster();
      }
    }

    final factory = bridge.sessionFactory ?? WebPeerSession.new;
    peer.session = factory(
      onState: state,
      onTextFrame: (frame) {
        if (current()) receiveText(peer, frame);
      },
      onControl: (control) {
        if (current()) receiveControl(peer, control);
      },
      onTransfer: (transfer) {
        if (current()) transferChanged(peer, transfer);
      },
      onError: (_) {
        if (current()) {
          store.setConversationOnline(id, online: connected.isNotEmpty);
        }
      },
    );
    peer.session.maxReassembledBytes = () =>
        store.largeMessageMode == LargeMessageMode.unlimited
        ? webPeerMaxReassembledBytes
        : kMaxFrameBytes;
    peer.proof = WebPeerEvidence(
      identity: identity,
      sendControl: peer.session.sendControl,
      onChange: () {
        if (current()) evidenceChanged(peer);
      },
    );
    peer.synchronize = () async {
      if (!current() || peer.session.state != 'connected') return;
      final book = store.orgCredentials,
          bundle = await store.orgCredentials.trustBundle();
      if (!current()) return;
      await peer.proof.setTrustBundle(
        jsonEncode({
          'id': bundle.id,
          'snapshot': bundle.snapshot,
          'revoked': bundle.revoked.toList(),
          'issuers': [
            for (final issuer in bundle.issuers)
              {
                'id': issuer.id,
                'name': issuer.name,
                'key': base64Encode(issuer.key),
                'policies': issuer.policies.toList(),
                'demo': issuer.demo,
              },
          ],
        }),
      );
      if (!current()) return;
      final credential = book.holderFor(identity);
      if (credential != null) {
        await peer.proof.setCredential(jsonEncode(credential.toWire()));
      } else {
        await peer.proof.clearCredential();
      }
    };
    peers[peer.id] = peer;
    return peer;
  }

  // 연결된 상대를 방에 들임 (온라인 표시·기능 알림·명단). 자동 초대 링크는 신원이 맞을 때만 불림
  void admit(_WebChatPeer peer, [Future<void>? proving]) {
    peer.opened = true;
    if (connected.length == 1) store.clearVerified(id);
    store.updateConversation(
      id,
      (c) => c.copyWith(
        online: true,
        secure: true,
        sas: peer.session.verificationCode,
      ),
    );
    unawaited(
      (proving ?? Future<void>.value())
          .then((_) => peer.syncOrganization())
          .catchError((Object _) {}),
    );
    sendTo(peer, {'k': 'rename', 'alias': identity.alias});
    sendTo(peer, {
      'k': 'native-room',
      'frame': {...webPeerCapabilities, 'platform': identity.platform},
    });
    roster();
    peer.settle(true);
  }

  void evidenceChanged(_WebChatPeer peer) {
    if (closing || bridge._disposed) return;
    final remote = peer.proof.peerIdentity;
    if (!acceptIdentity(peer) || !peer.bound) return;
    if (remote != null && store.conversation(id)?.isRoom != true) {
      store.updateConversation(id, (c) => c.copyWith(peerId: remote.peerId));
    }
    for (final entry in peer.proof.evidence.entries) {
      if (!peer.mirrored.add(entry.attestation.eventId)) continue;
      store.evidence.record(
        entry.attestation,
        verified: entry.status != EvidenceStatus.rejected,
        conversationId: id,
        transferId: entry.transferId,
      );
    }
    if (peer.proof.peerIdentity != null) {
      for (final control in peer.pendingNative.toList()) {
        peer.pendingNative.remove(control);
        receiveControl(peer, control);
      }
      if (hosting) nativeRoster();
    }
    recordOrganization(peer);
  }

  // 화면은 1:1이면 상대 신원(conversation.peerId)으로, 방이면 멤버 슬롯 id로 찾음: 호스트 1:1도 신원 키로 둠
  void recordOrganization(_WebChatPeer peer) {
    final org = peer.proof.organization;
    if (org == null) return forgetOrganization(peer);
    final key = hosting && store.conversation(id)?.isRoom == true
        ? peer.id
        : peer.proof.peerIdentity?.peerId ?? peer.id;
    if (peer.organizationPeerId != key) forgetOrganization(peer);
    mirrorOrganization(
      () => store.orgCredentials.record(key, org, owner: peer),
    );
    peer.organizationPeerId = key;
  }

  void forgetOrganization(_WebChatPeer peer) {
    final key = peer.organizationPeerId;
    if (key != null) {
      mirrorOrganization(() => store.orgCredentials.forget(key, owner: peer));
    }
    peer.organizationPeerId = null;
  }

  void mirrorOrganization(void Function() update) {
    bridge._mirroringOrganization = true;
    try {
      update();
    } finally {
      bridge._mirroringOrganization = false;
    }
  }

  void sendTo(_WebChatPeer peer, Map<String, dynamic> control) {
    if (peer.session.state != 'connected' || closing) return;
    unawaited(peer.session.sendControl(control).catchError((Object _) {}));
  }

  void broadcast(Map<String, dynamic> control, [_WebChatPeer? except]) {
    for (final peer in connected) {
      if (peer != except) sendTo(peer, control);
    }
  }

  void roster() {
    if (!hosting || closing) return;
    final online = connected.toList();
    final group = online.length > 1;
    final wasRoom = store.conversation(id)?.isRoom == true;
    members = {
      selfId: identity.alias,
      for (final peer in online) peer.id: peer.alias,
    };
    store.updateConversation(
      id,
      (c) => c.copyWith(
        online: online.isNotEmpty,
        isRoom: group || c.isRoom,
        localVerified: group ? false : c.localVerified,
        peerVerified: group ? false : c.peerVerified,
        memberCount: online.length + 1,
        peerAlias: group
            ? 'Web room'
            : online.firstOrNull?.alias ?? c.peerAlias,
        members: {
          for (final peer in online)
            peer.id: RoomMember(
              alias: peer.alias,
              platform: peer.platform,
              sas: peer.session.verificationCode,
              localVerified:
                  c.members[peer.id]?.localVerified == true ||
                  !c.isRoom &&
                      c.members.containsKey(peer.id) &&
                      c.localVerified,
              peerVerified:
                  c.members[peer.id]?.peerVerified == true ||
                  !c.isRoom && c.members.containsKey(peer.id) && c.peerVerified,
            ),
        },
        roomRecipientIds: online.map((p) => p.id).toList(),
      ),
    );
    nativeRoster();
    // 1:1이 방이 되면 자격 키가 신원에서 멤버 슬롯으로 바뀜
    if (group && !wasRoom) online.forEach(recordOrganization);
    for (final peer in online) {
      sendTo(peer, {
        'k': 'room-state',
        'self': peer.id,
        'host': selfId,
        'members': [
          for (final item in members.entries)
            {'id': item.key, 'alias': item.value},
        ],
      });
    }
  }
}
