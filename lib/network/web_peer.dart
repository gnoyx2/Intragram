import 'dart:async';
import 'dart:convert';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart' show DartHashSink, DartSha256;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intragram/core/constants.dart' show kFrameCeilingBytes;
import 'package:intragram/core/path_safety.dart' show safeBasename;

import 'web_peer_protocol.dart';
import 'web_stream_io.dart'
    show
        WebByteSource,
        WebReceiveSink,
        discardCommittedWebFile,
        rechunkByteStream;
export 'web_peer_protocol.dart'
    show WebPeerProblem, webPeerMaxFileBytes, webPeerMaxStreamFileBytes;

part 'web_peer_connection.dart';
part 'web_peer_files.dart';
part 'web_peer_parts.dart';
part 'web_peer_queue.dart';
part 'web_peer_receive.dart';
part 'web_peer_stream.dart';

const _active = {'offered', 'transferring'};
const _bufferLimit = 256 * 1024;
typedef WebPeerConnectionFactory =
    Future<RTCPeerConnection> Function(Map<String, dynamic> configuration);

final class WebPeerTransfer {
  const WebPeerTransfer({
    required this.id,
    required this.name,
    required this.direction,
    required this.state,
    required this.size,
    required this.transferred,
    this.bytes,
    this.origin,
    this.alias,
    this.localPath,
    this.sha256B64,
    this.stream = false,
    this.batch,
  });
  final String id, name, direction, state;
  final int size, transferred;
  final Uint8List? bytes;
  final String? origin, alias, localPath, sha256B64, batch;
  final bool stream;
}

// The browser and this client use the same SCTP-over-DTLS protocol, never HTTP.
class WebPeerSession {
  WebPeerSession({
    this.onState,
    this.onMessage,
    this.onTextFrame,
    this.onTransfer,
    this.onControl,
    this.onError,
    WebPeerConnectionFactory? connectionFactory,
  }) : _connectionFactory =
           connectionFactory ?? ((config) => createPeerConnection(config));

  final void Function(String state)? onState;
  final void Function(String text)? onMessage;
  final void Function(Map<String, dynamic> frame)? onTextFrame;
  final void Function(WebPeerTransfer transfer)? onTransfer;
  final void Function(Map<String, dynamic> control)? onControl;
  final void Function(Object error)? onError;
  final WebPeerConnectionFactory _connectionFactory;
  String state = 'idle';
  String verificationCode = '';
  String sessionBinding = '';
  RTCPeerConnection? _pc;
  RTCDataChannel? _channel;
  // 끝나지 않은 전송(제안 순서)과 빈 자리를 기다리는 수락(수락 순서). 바이트는 방향마다 lanes개까지 흐름
  final _inbound = <String, _Transfer>{}, _outbound = <String, _Transfer>{};
  final _startQueue = <_Transfer>[], _acceptQueue = <_Transfer>[];
  // 상대가 capabilities로 알린 동시 전송 수. 모르면 1이라 방향마다 한 파일씩 흐름
  int peerLanes = 1;
  final _seen = <String>{};
  final _parts = <String, _PartBuffer>{};
  // 다중 파트로 모을 상한. 받는 쪽 긴 메시지 설정을 따름 (v7: inline·spill 2 MiB 프레임,
  // unlimited는 64 MiB 글에 JSON 이스케이프 몫을 더한 webPeerMaxReassembledBytes)
  int Function() maxReassembledBytes = () => webPeerMaxReassembledBytes;
  // 다중 파트 메시지는 링크마다 하나씩 차례로 보냄
  Future<void> _partsTail = Future<void>.value();
  final _pendingData = <RTCDataChannelMessage>[];
  int _pendingBytes = 0;
  final _waiters = <void Function()>{};
  Timer? _connectTimer, _disconnectTimer;
  Future<void>? _closing;
  Future<void> _sendQueue = Future<void>.value();
  int _generation = 0;

  void _state(String next) {
    if (state == next) return;
    state = next;
    onState?.call(next);
    if (next == 'connected') {
      final pending = _pendingData.toList();
      _pendingData.clear();
      _pendingBytes = 0;
      for (final data in pending) {
        if (state != 'connected') break;
        _handleData(data);
      }
    }
  }

  Future<String> createOffer() => _createOffer();
  Future<String> acceptOffer(String code) => _acceptOffer(code);
  Future<void> acceptAnswer(String code) => _acceptAnswer(code);
  Future<String> offerBytes(String name, Uint8List bytes) =>
      _offerBytes(name, bytes);
  // The bridge owns this snapshot until every recipient releases it.
  // batch가 있으면 앞 파일이 오가는 중에도 제안만 먼저 보냄 (상대가 묶음을 지원할 때만 씀)
  Future<String> offerPreparedBytes(
    String name,
    Uint8List bytes, {
    String? id,
    String? origin,
    String? alias,
    String? batch,
  }) => _offerBytes(
    name,
    bytes,
    copy: false,
    id: id,
    origin: origin,
    alias: alias,
    batch: batch,
  );
  Future<String> offerStream(
    String name,
    WebByteSource source, {
    String? id,
    String? origin,
    String? alias,
    String? batch,
    void Function(String sha256B64)? onDigest,
  }) => _offerStream(
    name,
    source,
    id: id,
    origin: origin,
    alias: alias,
    batch: batch,
    onDigest: onDigest,
  );
  Future<void> acceptFile(String id) => _acceptFile(id);
  Future<void> acceptFileStream(
    String id,
    WebReceiveSink sink, {
    bool Function()? wanted,
  }) => _acceptFileStream(id, sink, wanted: wanted);
  Future<void> rejectFile(String id) => _rejectFile(id);
  Future<void> cancelFile(String id) => _cancelFile(id);
  // 지금 수락하면 바이트가 바로 흐르지 않고 빈 자리를 기다림
  bool get receiveLanesBusy => _receiving >= _receiveLanes;

  Future<List<StatsReport>> getStats() async => await _pc?.getStats() ?? [];

  Future<void> _send(Map<String, dynamic> frame) async {
    final raw = jsonEncode(frame);
    webPeerParseFrame(raw);
    await _sendRaw(RTCDataChannelMessage(raw));
  }

  Future<void> _sendRaw(RTCDataChannelMessage data) {
    final channel = _channel;
    if (state != 'connected' ||
        channel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw const WebPeerProblem('not-connected');
    }
    final operation = _sendQueue.then((_) async {
      if (_channel != channel || state != 'connected') {
        throw const WebPeerProblem('session-closed');
      }
      await channel!.send(data);
    });
    _sendQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<String> sendText(
    String text, {
    String? id,
    int maxBytes = webPeerMaxTextBytes,
  }) => _sendText(text, id: id, maxBytes: maxBytes);

  Future<void> sendControl(Map<String, dynamic> control) =>
      _sendControl(control);

  void _fail(Object error) {
    if (state == 'closed') return;
    unawaited(close());
    onError?.call(error);
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _generation++;
    _connectTimer?.cancel();
    _disconnectTimer?.cancel();
    final channel = _channel;
    final pc = _pc;
    _channel = null;
    _pc = null;
    verificationCode = '';
    sessionBinding = '';
    _state('closed');
    for (final cancel in _waiters.toList()) {
      cancel();
    }
    for (final transfer in [..._inbound.values, ..._outbound.values]) {
      if (_active.contains(transfer.state)) _finish(transfer, 'failed');
    }
    _clearParts();
    _seen.clear();
    _pendingData.clear();
    _pendingBytes = 0;
    if (channel != null) {
      channel.onDataChannelState = null;
      channel.onMessage = null;
      try {
        await channel.close();
      } on Object {
        /* Already closed by the peer. */
      }
    }
    if (pc != null) {
      pc.onConnectionState = null;
      pc.onDataChannel = null;
      pc.onIceGatheringState = null;
      try {
        await pc.close();
      } finally {
        await pc.dispose();
      }
    }
  }
}
