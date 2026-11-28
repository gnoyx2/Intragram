part of '../link_registry.dart';

// 인바운드 링크가 hello로 정체를 밝힌 뒤의 중복 정리
mixin _LinkRegistryDuplicates on _LinkRegistryState, _LinkRegistryRoom {
  // 동일 상대의 기존 1:1 대화가 남아 있으면(재연결) 임시 대화를 제거하고 기존 대화로 통합함 (동일 기기가 중복 표시되는 것을 방지함).
  // host만 확인하면 DHCP로 동일 IP를 할당받은 다른 기기가 통합될 위험이 있어 검증된 peerId 일치 여부까지 확인함
  void _mergeDuplicateHost(PeerLink link) {
    final provisional = link.conversationId;
    final host = link.remoteHost;
    final linkPeerId = link.remotePeerId;
    if (host == null || linkPeerId == null) return;
    // IP로 다이얼한 링크는 상대가 이 peerId의 신원 키를 증명했으니 주소가 바뀌었어도 같은 상대임 (끊긴 대화로만 합침)
    final dup = store.conversations.firstWhereOrNull(
      (c) =>
          c.id != provisional &&
          (c.peerHost == host ||
              link.dialledByUs && (_links[c.id]?.isClosed ?? true)) &&
          !c.isRoom &&
          c.peerId == linkPeerId,
    );
    if (dup != null) {
      _links.remove(provisional);
      store.wipeConversation(provisional);
      final stale = _links[dup.id];
      link.conversationId = dup.id;
      _adoptLink(dup.id, link);
      if (stale != null && !identical(stale, link)) {
        // 그 자리의 이전 링크는 _adoptLink가 이미 대체 표시함. 실제로 닫아서 소켓까지 정리함
        unawaited(stale.close());
      }
      store.updateConversation(dup.id, (c) => c.copyWith(peerId: linkPeerId));
      return;
    }
    // 1:1이 없으면 내 앱 그룹 방 멤버가 다시 붙은 건지 봄. 맞으면 방으로 되돌림 (안 그러면 따로 노는 1:1이 됨)
    final roomId = _appRoomId;
    final peerId = link.remotePeerId;
    if (roomId != null &&
        peerId != null &&
        (store.conversation(roomId)?.members.containsKey(peerId) ?? false)) {
      _joinAppRoom(link);
      // 끊긴 사이 인원이 바뀌었을 수 있어서 바로 알려 줌
      unawaited(_sendRoomJoin(link, roomId));
    }
  }

  // 같은 상대(검증된 peerId)의 끊긴 앱 1:1. 홈 타일·기기 코드로 다시 붙을 때 새 대화 대신 이 대화로 다시 검
  Conversation? _offlineChatWith(String peerId) =>
      store.conversations.firstWhereOrNull(
        (c) =>
            !c.isRoom &&
            c.transport == PeerTransport.app &&
            c.peerId == peerId &&
            (_links[c.id]?.isClosed ?? true),
      );

  // IP만 친 연결은 hello로 누군지 안 뒤 같은 상대의 끊긴 1:1로 옮겨 탐(_mergeDuplicateHost, 안 그러면 미검증 대화가 하나 더 생김).
  // 화면이 옮긴 대화를 열도록 확인이 끝날 때까지(최대 핸드셰이크 시간) 기다렸다가 최종 id를 돌려줌
  Future<String> _settleManualDial(String provisional) async {
    final link = _links[provisional];
    if (link == null) return provisional;
    final deadline = DateTime.now().add(kHandshakeTimeout);
    while (link.remotePeerId == null &&
        !link.isClosed &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return link.conversationId;
  }
}
