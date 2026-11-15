part of 'peer_link.dart';

// IGW1 코드 상한(48 KiB)보다 조금 넉넉한 프레임 가드. 코드 내용은 받는 쪽 WebRTC 계층이 다시 검증함
const int _kMaxWebSignalChars = 64 * 1024;

// 앱끼리 이미 이어진 암호 링크가 WebRTC 초대·응답 코드를 대신 나름: 사람이 코드를 옮기지 않고 근처 앱을 WebRTC 방에 데려옴.
// 이 링크 한 홉에서만 쓰고 방에 중계하지 않음. 이 프레임을 모르는 옛 앱은 그냥 버려서 보낸 쪽이 시간 초과로 앎
extension PeerLinkWebSignal on PeerLink {
  Future<bool> sendWebInvite(String id, String code) =>
      deliverRawInner({'k': 'web_invite', 'id': id, 'code': code});

  // code가 없으면 거절·실패
  Future<bool> sendWebAnswer(String id, [String? code]) =>
      deliverRawInner({'k': 'web_answer', 'id': id, 'code': ?code});

  // 방 초대(room_join, _authorizeRoomControl)와 같은 조건: 이미 내가 들어간 방의 호스트이거나, 이 1:1 대화의 그 상대이면서
  // 내가 건 상대 또는 양쪽이 코드를 확인한 상대. 내가 호스트인 방의 멤버나 웹 게스트의 초대는 받지 않음
  bool get _acceptsWebInvite {
    final peerId = remotePeerId;
    if (peerId == null) return false;
    if (_roomRole == _RoomLinkRole.remoteHost) return true;
    if (_roomRole != _RoomLinkRole.direct) return false;
    final conversation = store.conversation(conversationId);
    return conversation != null &&
        !conversation.isRoom &&
        conversation.peerId == peerId &&
        (dialledByUs || conversation.verified);
  }

  void _receiveWebSignal(Map<String, dynamic> raw) {
    final id = wireId(raw['id']);
    final code = raw['code'];
    if (!isSecure ||
        _superseded ||
        id == null ||
        code is! String? ||
        (code != null && code.length > _kMaxWebSignalChars)) {
      return;
    }
    if (raw['k'] == 'web_answer') {
      onWebAnswer?.call(id, code);
      return;
    }
    if (code == null) return;
    final join = onWebInvite;
    if (join == null || !_acceptsWebInvite) {
      unawaited(sendWebAnswer(id));
      return;
    }
    join(id, code);
  }
}
