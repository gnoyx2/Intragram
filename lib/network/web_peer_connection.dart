part of 'web_peer.dart';

const _dataOnlyConstraints = <String, dynamic>{
  'mandatory': {'OfferToReceiveAudio': false, 'OfferToReceiveVideo': false},
  'optional': <dynamic>[],
};

extension _WebPeerConnection on WebPeerSession {
  Future<RTCPeerConnection> _prepare() async {
    if (state != 'idle') throw const WebPeerProblem('session-in-use');
    _state('gathering');
    final generation = _generation;
    final pc = await _connectionFactory({
      'iceServers': <dynamic>[],
      'iceCandidatePoolSize': 0,
    });
    if (generation != _generation) {
      await pc.close();
      await pc.dispose();
      throw const WebPeerProblem('session-closed');
    }
    _pc = pc;
    pc.onDataChannel = (channel) {
      if (_pc != pc) {
        unawaited(channel.close());
        return;
      }
      if (_channel != null || channel.label != 'intragram-web-v1') {
        unawaited(channel.close());
        _fail(const WebPeerProblem('invalid-channel'));
        return;
      }
      _attach(channel);
    };
    pc.onConnectionState = (next) {
      if (_pc != pc) return;
      _disconnectTimer?.cancel();
      if (next == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          next == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _fail(const WebPeerProblem('connection-failed'));
      } else if (next ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _state('disconnected');
        _disconnectTimer = Timer(
          const Duration(seconds: 10),
          () => _fail(const WebPeerProblem('connection-failed')),
        );
      } else if (next ==
              RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
          _channel?.state == RTCDataChannelState.RTCDataChannelOpen &&
          verificationCode.isNotEmpty) {
        _state('connected');
      }
    };
    return pc;
  }

  Future<String> _description(RTCPeerConnection pc) async {
    if (pc.iceGatheringState !=
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      final done = Completer<void>();
      void cancel() {
        if (!done.isCompleted) {
          done.completeError(const WebPeerProblem('session-closed'));
        }
      }

      _waiters.add(cancel);
      pc.onIceGatheringState = (next) {
        if (next == RTCIceGatheringState.RTCIceGatheringStateComplete &&
            !done.isCompleted) {
          done.complete();
        }
      };
      if (await pc.getIceGatheringState() ==
              RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !done.isCompleted) {
        done.complete();
      }
      try {
        await done.future.timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw const WebPeerProblem('ice-timeout'),
        );
      } finally {
        _waiters.remove(cancel);
        pc.onIceGatheringState = null;
      }
    }
    if (_pc != pc) throw const WebPeerProblem('session-closed');
    final description = await pc.getLocalDescription();
    if (_pc != pc || description == null) {
      throw const WebPeerProblem('session-closed');
    }
    return webPeerEncodeDescription(description);
  }

  void _connectionDeadline() {
    _connectTimer?.cancel();
    if (state != 'connected') {
      _connectTimer = Timer(
        const Duration(seconds: 120),
        () => _fail(const WebPeerProblem('connection-timeout')),
      );
    }
  }

  void _attach(RTCDataChannel channel) {
    _channel = channel;
    channel.bufferedAmountLowThreshold = _bufferLimit ~/ 2;
    void update(RTCDataChannelState next) {
      if (_channel != channel) return;
      if (next == RTCDataChannelState.RTCDataChannelOpen) {
        _connectTimer?.cancel();
        unawaited(
          _fingerprint()
              .then((_) {
                if (_channel == channel &&
                    channel.state == RTCDataChannelState.RTCDataChannelOpen) {
                  _state('connected');
                }
              })
              .catchError((Object error) {
                if (_channel == channel) _fail(error);
              }),
        );
      } else if (next == RTCDataChannelState.RTCDataChannelClosed) {
        _fail(const WebPeerProblem('connection-closed'));
      }
    }

    channel.onDataChannelState = update;
    channel.onMessage = (data) {
      if (_channel != channel) return;
      _handleData(data);
    };
    if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      update(channel.state!);
    }
  }

  Future<void> _fingerprint() async {
    final pc = _pc;
    if (pc == null) throw const WebPeerProblem('session-closed');
    final local = await pc.getLocalDescription();
    final remote = await pc.getRemoteDescription();
    final fingerprints = [local, remote].map((description) {
      final match = RegExp(
        r'^a=fingerprint:sha-256 (.+)$',
        caseSensitive: false,
        multiLine: true,
      ).firstMatch(description?.sdp ?? '');
      if (match == null) throw const WebPeerProblem('invalid-code');
      return match[1]!.trim().toUpperCase();
    }).toList()..sort();
    final hash = await Sha256().hash(utf8.encode(fingerprints.join('|')));
    if (_pc != pc) return;
    sessionBinding = base64Encode(hash.bytes);
    verificationCode =
        (ByteData.sublistView(Uint8List.fromList(hash.bytes)).getUint32(0) %
                1000000)
            .toString()
            .padLeft(6, '0');
  }
}

extension _WebPeerNegotiation on WebPeerSession {
  Future<String> _createOffer() async {
    if (state != 'idle') throw const WebPeerProblem('session-in-use');
    try {
      final pc = await _prepare();
      final channel = await pc.createDataChannel(
        'intragram-web-v1',
        RTCDataChannelInit()..ordered = true,
      );
      if (_pc != pc) {
        await channel.close();
        throw const WebPeerProblem('session-closed');
      }
      _attach(channel);
      await pc.setLocalDescription(await pc.createOffer(_dataOnlyConstraints));
      final code = await _description(pc);
      _state('waiting');
      return code;
    } on Object {
      await close();
      rethrow;
    }
  }

  Future<String> _acceptOffer(String code) async {
    final offer = webPeerDecodeCode(code, 'offer');
    if (state != 'idle') throw const WebPeerProblem('session-in-use');
    try {
      final pc = await _prepare();
      await pc.setRemoteDescription(offer);
      await pc.setLocalDescription(await pc.createAnswer(_dataOnlyConstraints));
      final answer = await _description(pc);
      if (state != 'connected') _state('connecting');
      _connectionDeadline();
      return answer;
    } on Object {
      await close();
      rethrow;
    }
  }

  Future<void> _acceptAnswer(String code) async {
    final answer = webPeerDecodeCode(code, 'answer');
    final pc = _pc;
    if (state != 'waiting' || pc == null) {
      throw const WebPeerProblem('unexpected-answer');
    }
    try {
      _state('connecting');
      await pc.setRemoteDescription(answer);
      if (_pc != pc) throw const WebPeerProblem('session-closed');
      _connectionDeadline();
    } on Object {
      await close();
      rethrow;
    }
  }
}
