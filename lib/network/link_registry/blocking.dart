part of '../link_registry.dart';

// 기기 차단과 '내가 연 대화만 받기'. 신원 키가 실행마다 새로 생겨서 차단도 이번 실행 동안만 RAM에 둠
// (상대가 앱을 다시 켜면 새 ID라 닿음: 그걸 막는 게 '내가 연 대화만 받기'). 웹 게스트는 해당 없음
mixin _LinkRegistryBlocking on _LinkRegistryState {
  bool isBlocked(String peerId) => _blockedPeers.contains(peerId);

  // 1:1 상대만 차단함 (v7 방은 호스트가 멤버를 관리함). 차단은 사람(신원) 단위라, 같은 사람과 따로 열린
  // 1:1 대화(v7 대화와 WebRTC 대화)를 모두 차단으로 표시하고 그 사람과의 v7·WebRTC 링크를 전부 끊음
  Future<void> blockPeer(String conversationId) async {
    final conversation = store.conversation(conversationId);
    final peerId = conversation?.peerId;
    if (conversation == null || conversation.isRoom || peerId == null) return;
    _blockedPeers.add(peerId);
    final chats = _chatsWith(peerId, conversationId);
    for (final id in chats) {
      store.updateConversation(id, (c) => c.copyWith(blocked: true));
    }
    for (final id in chats) {
      await _links[id]?.close();
      if (_web.contains(id)) await _web.closeRoom(id);
    }
    // 그 사람이 들어와 있는 WebRTC 방(내가 호스트든 멤버든)의 링크
    await _web.closePeer(peerId);
    store.addSystemMessage(
      conversationId,
      const SystemEvent(SystemEventKind.peerBlocked),
    );
  }

  void unblockPeer(String conversationId) {
    final peerId = store.conversation(conversationId)?.peerId;
    if (peerId == null) return;
    _blockedPeers.remove(peerId);
    for (final id in _chatsWith(peerId, conversationId)) {
      store.updateConversation(id, (c) => c.copyWith(blocked: false));
    }
  }

  // 그 신원과의 1:1 대화 전부 (지금 고른 대화 포함)
  List<String> _chatsWith(String peerId, String conversationId) => [
    conversationId,
    for (final c in store.conversations)
      if (c.id != conversationId && !c.isRoom && c.peerId == peerId) c.id,
  ];

  // 모르는 기기 = 이번 세션의 어느 대화·방 멤버에도 없는 peerId. 인바운드 거절 이유는 화면에 안 남아서 아무거나 씀
  @override
  SystemEventKind? _refusal(String peerId, {required bool dialledByUs}) {
    if (_blockedPeers.contains(peerId)) return SystemEventKind.peerBlocked;
    if (dialledByUs || !store.onlyChatsIStart) return null;
    final known = store.conversations.any(
      (c) => c.peerId == peerId || c.members.containsKey(peerId),
    );
    return known ? null : SystemEventKind.handshakeFailed;
  }
}
