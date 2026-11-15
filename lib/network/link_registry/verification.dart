part of '../link_registry.dart';

mixin _LinkRegistryVerification on _LinkRegistryState {
  // 양쪽 다 눌러야 확인 완료 (상대가 아직이면 UI는 '대기 중'). expectedSas는 대화상자에 띄웠던 코드: 그사이 재연결로 바뀌었으면 무시
  void markVerified(String conversationId, {required String? expectedSas}) {
    final conversation = store.conversation(conversationId);
    if (expectedSas == null ||
        conversation == null ||
        conversation.sas != expectedSas) {
      return;
    }
    final alreadyMutual = conversation.peerVerified;
    store.setLocalVerified(conversationId);
    store.addSystemMessage(
      conversationId,
      SystemEvent(
        alreadyMutual
            ? SystemEventKind.mutuallyVerified
            : SystemEventKind.markedVerified,
      ),
    );
    if (_web.contains(conversationId)) {
      _web.verify(conversationId, sas: expectedSas);
      return;
    }
    final link = _links[conversationId];
    if (link != null) unawaited(link.sendRawInnerOrClose(InnerFrame.verify()));
  }

  // markVerified의 방 멤버판: 대화 전체가 아니라 그 멤버 슬롯만 바꿈
  void markRoomMemberVerified(
    String conversationId,
    String peerId, {
    required String? expectedSas,
  }) {
    final member = store.conversation(conversationId)?.members[peerId];
    if (expectedSas == null || member == null || member.sas != expectedSas) {
      return;
    }
    final alreadyMutual = member.peerVerified;
    store.setRoomMemberLocalVerified(conversationId, peerId);
    store.addSystemMessage(
      conversationId,
      SystemEvent(
        alreadyMutual
            ? SystemEventKind.mutuallyVerified
            : SystemEventKind.markedVerified,
      ),
    );
    if (_web.contains(conversationId)) {
      _web.verify(conversationId, peerId: peerId, sas: expectedSas);
      return;
    }
    final link = _linkToMember(conversationId, peerId);
    if (link != null) unawaited(link.sendRawInnerOrClose(InnerFrame.verify()));
  }

  // 숫자가 다름(버튼이나 다른 코드 스캔): 중간자일 수 있어서 그 링크를 바로 닫고 경고 줄을 남김
  Future<void> reportSasMismatch(
    String conversationId, {
    String? memberPeerId,
  }) async {
    store.addSystemMessage(
      conversationId,
      const SystemEvent(SystemEventKind.sasMismatch),
    );
    // 재연결이 예전 확인을 이어 가지 않게 지움 (_carryVerification)
    store.clearVerified(conversationId);
    final link = memberPeerId == null
        ? _links[conversationId]
        : _linkToMember(conversationId, memberPeerId);
    await link?.close();
    if (_web.contains(conversationId)) await _web.closeRoom(conversationId);
  }

  // 호스트면 그 멤버의 지금 링크만 봄 (재접속 직후엔 닫히는 중인 옛 링크가 아직 목록에 있음). 멤버면 호스트 링크 하나뿐
  PeerLink? _linkToMember(String conversationId, String peerId) =>
      _isRoomHub(conversationId)
      ? _memberLinks(
          conversationId,
        ).firstWhereOrNull((l) => l.remotePeerId == peerId)
      : _links[conversationId];
}
