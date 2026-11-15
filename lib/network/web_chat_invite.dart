part of 'web_chat_bridge.dart';

extension WebChatInvitations on WebChatBridge {
  _WebChatPeer _newInvitee(_WebRoom room) {
    room.peers.removeWhere((_, peer) => peer.session.state == 'closed');
    if (room.connected.isEmpty && room.hosting) {
      room.closing = false;
    }
    if (!room.hosting || room.peers.length >= webPeerMaxRoomMembers - 1) {
      throw const WebPeerProblem('room-full');
    }
    return room.addPeer(true);
  }

  // 손으로 옮기는 초대만 봄: 앱 링크가 대신 나르는 자동 초대는 자기 응답을 직접 받음
  Iterable<_WebChatPeer> _manualPending(_WebRoom? room) =>
      room?.peers.values.where((p) => !p.automatic) ?? const [];

  Future<void> acceptAnswer(String id, String code) async {
    final pending = _manualPending(
      rooms[id],
    ).where((p) => p.session.state == 'waiting').lastOrNull;
    if (pending == null) throw const WebPeerProblem('unexpected-answer');
    await pending.session.acceptAnswer(code);
  }

  Future<void> cancelInvitation(String id) async {
    final room = rooms[id];
    if (room == null) return;
    final pending = _manualPending(room).where((p) => !p.opened).toList();
    for (final peer in pending) {
      await peer.session.close();
      room.peers.remove(peer.id);
    }
    room.roster();
  }

  // 앱끼리 이미 이어진 암호 링크가 초대·응답 코드를 대신 나름: exchange가 초대 코드를 보내고 상대의 응답 코드를 돌려줌.
  // 새 WebRTC 링크가 그 앱(expectedPeerId)의 신원을 증명하고 방에 들어올 때까지 기다림: 응답을 다른 기기가
  // 만들었거나 deadline 안에 못 들어오면 끊고 실패로 알림
  Future<void> inviteThrough(
    String id,
    String expectedPeerId,
    Future<String> Function(String invitation) exchange,
    Duration deadline,
  ) async {
    final room = rooms[id];
    if (room == null || _disposed) throw const WebPeerProblem('room-full');
    final entered = Completer<bool>();
    final peer = _newInvitee(room)
      ..automatic = true
      ..expectedPeerId = expectedPeerId
      ..joined = entered;
    try {
      final answer = await exchange(await peer.session.createOffer());
      await peer.session.acceptAnswer(answer);
      if (!await entered.future.timeout(deadline, onTimeout: () => false)) {
        throw const WebPeerProblem('auto-invite-failed');
      }
    } on Object {
      room.peers.remove(peer.id);
      await peer.session.close();
      room.roster();
      rethrow;
    }
  }

  // 차단한 신원의 WebRTC 링크를 모든 방에서 끊음 (v7 대화에서 차단해도 따로 열린 WebRTC 방에 남지 않음)
  Future<void> closePeer(String peerId) => Future.wait([
    for (final room in rooms.values)
      for (final peer in room.peers.values.toList())
        if (peer.proof.peerIdentity?.peerId == peerId) peer.session.close(),
  ]);

  // 내가 호스트라 사람을 더 넣을 수 있는 방인지
  bool hosts(String id) => rooms[id]?.hosting ?? false;

  // 그 신원(앱 peerId)이 이미 이 방에 이어져 있는지 (같은 앱을 두 번 초대하지 않음)
  bool hasMember(String id, String peerId) =>
      rooms[id]?.connected.any((p) => p.proof.peerIdentity?.peerId == peerId) ??
      false;

  // 이어졌거나 이어지는 중인 링크가 있는 방
  bool isLive(String id) {
    final room = rooms[id];
    return room != null &&
        !room.closing &&
        room.peers.values.any((p) => p.session.state != 'closed');
  }

  bool everOpened(String id) =>
      rooms[id]?.peers.values.any((p) => p.opened) ?? false;
}

class _WebChatPeer {
  _WebChatPeer(this.id, this.dialled);
  final String id;
  final bool dialled;
  String alias = 'Web', platform = 'Browser';
  bool nativeRoom = false;
  // 파일 여러 개를 한꺼번에 제안해도 되는 상대 (보조 HTML 클라이언트는 하나씩만 받음)
  bool batchOffers = false;
  bool opened = false, automatic = false;
  // 자동 초대 링크가 붙어야 하는 신원 (초대·응답을 나른 앱 링크의 peerId). 증명될 때까지 방 멤버로 치지 않음
  String? expectedPeerId;
  // 자동 초대의 결과를 기다리는 쪽: 방에 들어오면 true, 그 전에 닫히면 false
  Completer<bool>? joined;
  String? organizationPeerId;
  final pendingNative = <Map<String, dynamic>>[];
  final pendingIdentity = <void Function()>[];
  Future<void> nativeQueue = Future<void>.value();
  // 이 상대에게 보낼 파일 제안 줄 (상대마다 따로라 답 없는 멤버가 다른 멤버를 막지 않음)
  Future<void> fileQueue = Future<void>.value();
  int queuedNative = 0;
  late WebPeerSession session;
  late WebPeerEvidence proof;
  final mirrored = <String>{};
  Future<void> Function()? synchronize;
  Future<void> syncOrganization() async => synchronize?.call();

  bool get bound =>
      expectedPeerId == null || proof.peerIdentity?.peerId == expectedPeerId;
  void settle(bool entered) {
    final waiting = joined;
    if (waiting != null && !waiting.isCompleted) waiting.complete(entered);
  }
}
