part of '../link_registry.dart';

// 방 초대가 상대 쪽 인가 규칙과 어긋나지 않게 거르는 도우미 (inviteToRoom·addPeersToRoom)
extension _RoomInviteGate on _LinkRegistryState {
  bool _isOpenRoomMember(String peerId) {
    final roomId = _appRoomId;
    return roomId != null &&
        _roomLinks.any(
          (l) =>
              l.conversationId == roomId &&
              !l.isClosed &&
              l.isSecure &&
              l.remotePeerId == peerId,
        );
  }

  // 상대는 1:1을 방으로 바꾸는 첫 room_join을 자기가 다이얼했거나 서로 코드를 확인한 링크에서만 받음 (_authorizeRoomControl).
  // 내가 다이얼한(재연결 포함) 미확인 링크를 방에 넣으면 상대는 조용히 1:1로 남고 나만 멤버로 세서, 방 글이 내 1:1 글로 보임.
  // 그래서 확인이 끝날 때까지 기다렸다 넣음. 내 verify 프레임이 room_join보다 먼저 나가서 상대도 그때는 확인된 상태임
  bool _memberWillAcceptRoom(PeerLink link) =>
      !link.dialledByUs ||
      (store.conversation(link.conversationId)?.verified ?? false);

  Future<void> _whenMemberWillAccept(
    PeerLink link,
    Future<void> Function() join,
  ) async {
    if (_memberWillAcceptRoom(link)) return join();
    store.addSystemMessage(
      link.conversationId,
      const SystemEvent(SystemEventKind.roomWaitsVerification),
    );
    StreamSubscription<List<Conversation>>? sub;
    var done = false;
    sub = store.watchConversations().listen((_) {
      if (done) return;
      if (link.isClosed || _disposed) {
        done = true;
        unawaited(sub?.cancel());
        return;
      }
      if (!_memberWillAcceptRoom(link)) return;
      done = true;
      unawaited(sub?.cancel());
      unawaited(join());
    });
  }
}
