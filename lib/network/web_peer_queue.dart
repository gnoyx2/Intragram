part of 'web_peer.dart';

// 제안은 여러 개를 한꺼번에 걸어 두고, 바이트는 방향마다 lanes개까지 동시에 흐름.
// lanes를 모르는 상대에겐 1개씩: 수락을 빈 자리가 날 때까지 미뤄 예전 순서를 지킴
extension _WebPeerQueue on WebPeerSession {
  int get _receiveLanes => min(webPeerLanes, peerLanes);
  int get _receiving =>
      _inbound.values.where((t) => t.state == 'transferring').length;
  int get _sending =>
      _outbound.values.where((t) => t.state == 'transferring').length;

  bool _queueOffer(Map<String, dynamic> frame) {
    final waiting = _inbound.values.where((t) => t.state == 'offered').length;
    if (waiting > webPeerMaxWaitingOffers) return false;
    final offer = _Transfer(
      id: frame['id'],
      // v7 제안처럼 상대가 정한 이름을 정제함 (RLO 등으로 확장자 위장 차단)
      name: safeBasename(frame['name'] as String),
      direction: 'receive',
      size: frame['size'],
      origin: frame['origin'],
      alias: frame['alias'],
      batch: frame['bid'],
      streamOffer: frame['stream'] == true,
    );
    _inbound[offer.id] = offer;
    _transfer(offer);
    return true;
  }

  // 고른 제안을 시작함. 자리가 다 찼으면 수락만 기록하고 앞 파일이 끝나면 수락한 순서대로 시작함
  Future<void> _claimIncoming(
    String id,
    Future<void> Function(_Transfer transfer) start, {
    WebReceiveSink? sink,
  }) async {
    final offer = _inbound[id];
    if (offer == null || offer.state != 'offered' || offer.start != null) {
      await sink?.abort();
      throw const WebPeerProblem('unknown-transfer');
    }
    if (_receiving >= _receiveLanes) {
      // sink는 수락할 때 이미 열려 있음: 폴더 선택과 용량 확인을 사용자가 누른 그 자리에서 끝냄 (자리가 날 때
      // 열면 창과 오류가 엉뚱한 때 뜸). 빈 파일뿐이고 대기 제안은 webPeerMaxWaitingOffers개까지.
      // 기다리다 닫히거나 취소되면 _finish가 sink를 버림
      offer
        ..sink = sink
        ..start = start;
      _startQueue.add(offer);
      // 수락은 했다고 알림: 보내는 쪽이 오래 답 없는 제안으로 보고 취소하지 않게 함.
      // lanes를 아는 상대만 이 프레임을 앎 (보조 HTML 클라이언트엔 보내지 않음)
      if (peerLanes > 1) {
        unawaited(
          _send({'kind': 'file-queued', 'id': id}).catchError((Object _) {}),
        );
      }
      return;
    }
    return start(offer);
  }

  void _nextIncoming() {
    while (state == 'connected' &&
        _receiving < _receiveLanes &&
        _startQueue.isNotEmpty) {
      final next = _startQueue.removeAt(0), start = next.start;
      next.start = null;
      if (start == null || !identical(_inbound[next.id], next)) continue;
      // 실패는 start가 _finish로 타일에 남김. start는 첫 await 전에 state를 transferring으로 바꿈
      unawaited(start(next).catchError((Object _) {}));
    }
  }

  // 받는 쪽이 고른 제안. 자리가 다 찼으면(lanes를 넘겨 수락한 상대) 줄 세웠다가 빈 자리에 시작함
  void _claimOutgoing(String id, bool peerStreams) {
    final offer = _outbound[id];
    if (offer == null || offer.state != 'offered' || offer.accepted) return;
    offer
      ..accepted = true
      ..peerStreams = peerStreams;
    if (_sending >= webPeerLanes) {
      _acceptQueue.add(offer);
      _transfer(offer);
      _watchQueuedClaims();
      return;
    }
    _startOutgoing(offer);
    _watchQueuedClaims();
  }

  // 받는 쪽이 수락해 흐르는(또는 우리 자리만 기다리는) 우리 전송이 있을 때만 상대 자리가 차 있을 수 있음
  bool get _peerBusy => _outbound.values.any(
    (t) => t.state == 'transferring' || t.state == 'offered' && t.accepted,
  );

  // 상대가 줄 세웠다고 알린 제안(file-queued)은 앞 전송이 흐르는 동안만 '수락됨'으로 침.
  // 흐르던 전송이 다 끝났는데 webPeerTransferTimeout 안에 수락이 안 오면 답 없는 제안으로 되돌림:
  // 줄만 세우고 수락하지 않는 상대가 보내는 쪽 송신 예산을 붙잡지 못함
  void _watchQueuedClaims() {
    final busy = _peerBusy;
    for (final offer in _outbound.values) {
      if (offer.state != 'offered' || !offer.peerQueued || offer.accepted) {
        continue;
      }
      if (busy) {
        offer.timer?.cancel();
        offer.timer = null;
        continue;
      }
      offer.timer ??= Timer(webPeerTransferTimeout, () {
        offer.timer = null;
        if (offer.state != 'offered' || offer.accepted || _peerBusy) return;
        offer.peerQueued = false;
        _transfer(offer);
      });
    }
  }

  void _nextOutgoing() {
    while (state == 'connected' &&
        _sending < webPeerLanes &&
        _acceptQueue.isNotEmpty) {
      final next = _acceptQueue.removeAt(0);
      if (next.state == 'offered' && identical(_outbound[next.id], next)) {
        _startOutgoing(next);
      }
    }
  }

  void _startOutgoing(_Transfer outgoing) {
    if (outgoing.source == null) {
      outgoing.state = 'transferring';
      _transfer(outgoing);
      unawaited(_stream(outgoing));
      return;
    }
    final peerStreams = outgoing.peerStreams;
    if (!peerStreams && outgoing.size > webPeerMaxFileBytes) {
      unawaited(
        _send({
          'kind': 'file-cancel',
          'id': outgoing.id,
        }).catchError((Object _) {}),
      );
      _finish(outgoing, 'failed');
      onError?.call(const WebPeerProblem('peer-file-limit'));
      return;
    }
    outgoing.streamMode = peerStreams;
    outgoing.creditOffset = peerStreams ? _streamWindowBytes : outgoing.size;
    outgoing.state = 'transferring';
    _transfer(outgoing);
    unawaited(_streamSource(outgoing));
  }

  // 끝난 전송을 빼고 빈 자리에 기다리던 수락을 이어 감
  void _dequeue(_Transfer transfer) {
    final receive = transfer.direction == 'receive';
    final open = receive ? _inbound : _outbound;
    if (identical(open[transfer.id], transfer)) open.remove(transfer.id);
    (receive ? _startQueue : _acceptQueue).remove(transfer);
    scheduleMicrotask(receive ? _nextIncoming : _nextOutgoing);
    if (!receive) _watchQueuedClaims();
  }
}
