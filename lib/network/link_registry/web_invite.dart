part of '../link_registry.dart';

// 자동 초대의 응답을 기다리는 시간 (상대의 ICE 후보 수집 12초 + 여유). 테스트만 줄여 씀
Duration webInviteTimeout = const Duration(seconds: 20);
// 자동 초대로 만든 WebRTC 링크가 이 안에 안 이어지면(신원 증명까지) 양쪽 모두 포기함:
// 받은 쪽은 빈 대화를 지우고, 보낸 쪽은 실패로 알림. 테스트만 줄여 씀
Duration webJoinDeadline = const Duration(seconds: 30);
// 자동 초대가 방을 못 연 채 끝난 링크는 이만큼 새 자동 초대를 안 받음: 초대만 되풀이해 WebRTC 연결 시도를
// 계속 일으킬 수 없음. 초대한 쪽에는 평소와 같은 거절이 감. 테스트만 줄여 씀
Duration webInviteCooldown = const Duration(seconds: 60);

// 앱 → 앱 WebRTC 자동 초대의 링크 쪽: 증명된 v7 링크가 IGW1 초대·응답 코드를 대신 나름.
// 브라우저는 TCP를 못 열어 v7 방에 못 들어오니, 브라우저가 있는 WebRTC 방으로 근처 앱을 코드 입력 없이 데려오는 길임
mixin _LinkRegistryWebSignals on _LinkRegistryState {
  // 보낸 초대 id → (보낸 링크, 응답). 응답은 초대를 보낸 그 링크에서 온 것만 받음
  final Map<String, (PeerLink, Completer<String?>)> _webAnswers = {};

  // 링크마다 자동으로 들어간 방 하나만 살려 둠 (초대를 퍼부어 연결·대화를 쌓지 못함). ''는 들어가는 중
  final Map<PeerLink, String> _webJoined = {};
  final Set<Timer> _webJoinTimers = {};
  // 링크 → 마지막 자동 초대 실패부터 잰 시간 (webInviteCooldown 동안 새 초대를 거절함)
  final Map<PeerLink, Stopwatch> _webFailed = {};

  void _noteWebFailure(PeerLink link) {
    if (!link.isClosed) _webFailed[link] = Stopwatch()..start();
  }

  void _wireWebSignals(PeerLink link) {
    link.onWebAnswer = (id, code) {
      final waiting = _webAnswers[id];
      if (waiting != null && identical(waiting.$1, link)) {
        _webAnswers.remove(id)!.$2.complete(code);
      }
    };
    link.onWebInvite = (id, code) =>
        unawaited(_joinWebRoomVia(link, id, code).catchError((Object _) {}));
  }

  // 초대 코드를 보내고 상대 앱의 응답 코드를 기다림
  Future<String> _exchangeWebCode(PeerLink link, String invitation) async {
    final id = newId();
    final answer = Completer<String?>();
    _webAnswers[id] = (link, answer);
    try {
      if (!link.isSecure || !await link.sendWebInvite(id, invitation)) {
        throw const WebPeerProblem('auto-invite-failed');
      }
      final code = await answer.future.timeout(
        webInviteTimeout,
        onTimeout: () => throw const WebPeerProblem('auto-invite-failed'),
      );
      if (code == null) throw const WebPeerProblem('auto-invite-refused');
      return code;
    } finally {
      _webAnswers.remove(id);
    }
  }

  // 링크가 닫히면 그 링크로 보낸 초대는 더 기다리지 않음
  void _forgetWebSignals(PeerLink link) {
    _webJoined.remove(link);
    _webFailed.remove(link);
    for (final id in _webAnswers.keys.toList()) {
      final waiting = _webAnswers[id]!;
      if (identical(waiting.$1, link)) {
        _webAnswers.remove(id);
        if (!waiting.$2.isCompleted) waiting.$2.complete(null);
      }
    }
  }

  Future<void> _joinWebRoomVia(PeerLink link, String id, String code) async {
    var live = _webJoined[link];
    final inviter = link.remotePeerId;
    // 앞선 자동 초대의 방이 한 번도 안 열린 채 죽어 있으면 기한 전이라도 실패로 적고 빈 대화를 치움
    if (live != null &&
        live.isNotEmpty &&
        !_web.isLive(live) &&
        !_web.everOpened(live)) {
      _webJoined.remove(link);
      _noteWebFailure(link);
      await _dropWebRoom(live);
      live = null;
    }
    final failed = _webFailed[link];
    if (_disposed ||
        link.isClosed ||
        inviter == null ||
        failed != null && failed.elapsed < webInviteCooldown ||
        live != null && (live.isEmpty || _web.isLive(live))) {
      await link.sendWebAnswer(id);
      return;
    }
    _webJoined[link] = '';
    final String roomId, answer;
    try {
      // 방의 상대는 초대를 나른 이 앱이어야 함: 다른 기기가 만든 초대 코드면 연결된 뒤 끊김
      (conversationId: roomId, code: answer) = await _web.joinInvitation(
        code,
        expectedPeerId: inviter,
      );
    } on Object {
      if (_webJoined[link] == '') _webJoined.remove(link);
      _noteWebFailure(link);
      await link.sendWebAnswer(id);
      return;
    }
    final sent =
        !_disposed && !link.isClosed && await link.sendWebAnswer(id, answer);
    // 응답을 보내는 사이 전체 정리(disposeAll)가 지나갔으면 방·타이머를 다시 만들지 않음
    if (!sent || _disposed) {
      _webJoined.remove(link);
      if (!_disposed) _noteWebFailure(link);
      await _dropWebRoom(roomId);
      return;
    }
    // 응답을 보내는 사이 링크가 닫혔으면 정리(_forgetWebSignals)가 이미 지나갔으니 닫힌 링크를 다시 적지 않음
    if (link.isClosed) {
      _webJoined.remove(link);
    } else {
      _webJoined[link] = roomId;
    }
    late final Timer timer;
    timer = Timer(webJoinDeadline, () {
      _webJoinTimers.remove(timer);
      if (_disposed || _web.everOpened(roomId)) return;
      // 이 방이 아직 그 링크의 시도일 때만 실패로 적음 (이미 치운 시도를 두 번 세지 않음)
      if (_webJoined[link] == roomId) {
        _webJoined.remove(link);
        _noteWebFailure(link);
      }
      unawaited(_dropWebRoom(roomId));
    });
    _webJoinTimers.add(timer);
  }

  Future<void> _dropWebRoom(String roomId) async {
    await _web.closeRoom(roomId);
    store.wipeConversation(roomId);
  }

  void _cancelWebJoinTimers() {
    for (final timer in _webJoinTimers) {
      timer.cancel();
    }
    _webJoinTimers.clear();
    _webAnswers.clear();
    _webJoined.clear();
    _webFailed.clear();
  }
}

// 자동 초대의 호스트 쪽 (다이얼이 필요해서 연결 믹스인 뒤에 옴)
mixin _LinkRegistryWebInvite
    on _LinkRegistryState, _LinkRegistryWebSignals, _LinkRegistryConnect {
  // 같은 (방, 상대)로 진행 중인 자동 초대
  final Set<String> _webInviting = {};

  // 내가 호스트인 WebRTC 방인지 (앱을 자동으로 초대할 수 있는 방)
  bool hostsWebRoom(String conversationId) => _web.hosts(conversationId);

  // 근처 앱을 내 WebRTC 방에 넣음: 증명된 v7 링크(없으면 다이얼)로 코드를 대신 교환함
  Future<void> inviteAppToWebRoom(String roomId, PeerDevice peer) async {
    final member = _roomLinks.lastWhereOrNull(
      (l) => !l.isClosed && l.isSecure && l.remotePeerId == peer.peerId,
    );
    final link =
        _existingLinkFor(peer)?.value ??
        member ??
        _links[await connectToPeer(peer)];
    if (link == null) throw const WebPeerProblem('auto-invite-failed');
    const step = Duration(milliseconds: 50);
    for (var waited = Duration.zero; !link.isSecure; waited += step) {
      if (link.isClosed || _disposed || waited > kHandshakeTimeout) {
        throw const WebPeerProblem('auto-invite-failed');
      }
      await Future<void>.delayed(step);
    }
    await _inviteLinkToWebRoom(roomId, link);
  }

  Future<void> _inviteLinkToWebRoom(String roomId, PeerLink link) async {
    final peerId = link.remotePeerId;
    // 신원이 없는 링크(레거시 포털의 브라우저 게스트)는 자동으로 못 데려옴
    if (peerId == null) throw const WebPeerProblem('auto-invite-failed');
    final key = '$roomId/$peerId';
    if (_web.hasMember(roomId, peerId) || !_webInviting.add(key)) return;
    try {
      await _web.inviteThrough(
        roomId,
        peerId,
        (code) => _exchangeWebCode(link, code),
        webJoinDeadline,
      );
    } finally {
      _webInviting.remove(key);
    }
  }

  // v7 대화(내 방이면 멤버 전원, 1:1이면 그 상대)의 앱들을 WebRTC 방으로 초대함. 받지 않은 상대 수를 돌려줌
  Future<int> inviteConversationToWebRoom(String from, String roomId) async {
    final hub = _isRoomHub(from);
    final links = hub ? _memberLinks(from) : [?_links[from]];
    // 끊겼거나 아직 증명 전인 상대도 못 데려온 것으로 셈 (1:1 상대가 오프라인이면 링크 자체가 없음)
    var failed =
        links.where((l) => !l.isSecure).length +
        (hub || links.isNotEmpty ? 0 : 1);
    await Future.wait([
      for (final link in links)
        if (link.isSecure)
          _inviteLinkToWebRoom(roomId, link).catchError((Object _) => failed++),
    ]);
    return failed;
  }

  // WebRTC 방에서 고른 근처 앱은 v7 방을 따로 만들지 않고 이 방으로 초대함
  @override
  Future<void> addPeersToRoom(
    String fromConversationId,
    List<PeerDevice> peers,
  ) async {
    if (!_web.contains(fromConversationId)) {
      return super.addPeersToRoom(fromConversationId, peers);
    }
    Object? error;
    await Future.wait([
      for (final peer in peers)
        inviteAppToWebRoom(
          fromConversationId,
          peer,
        ).catchError((Object caught) => error ??= caught),
    ]);
    if (error != null) throw error!;
  }
}
