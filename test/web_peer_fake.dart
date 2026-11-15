import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

String webPeerTestSdp(String fingerprint) => [
  'v=0',
  'o=- 1 1 IN IP4 127.0.0.1',
  's=-',
  't=0 0',
  'a=group:BUNDLE 0',
  'm=application 9 UDP/DTLS/SCTP webrtc-datachannel',
  'c=IN IP4 0.0.0.0',
  'a=mid:0',
  'a=ice-ufrag:abcd',
  'a=ice-pwd:abcdefghijklmnopqrstuvwx',
  'a=fingerprint:sha-256 ${List.filled(32, fingerprint).join(':')}',
  'a=setup:actpass',
  'a=sctp-port:5000',
  'a=candidate:1 1 udp 1234 192.168.1.2 4567 typ host',
  '',
].join('\r\n');

class WebPeerFakeChannel extends RTCDataChannel {
  WebPeerFakeChannel();
  WebPeerFakeChannel? peer;
  final sent = <RTCDataChannelMessage>[];
  int buffer = 0;
  @override
  String get label => 'intragram-web-v1';
  @override
  RTCDataChannelState state = RTCDataChannelState.RTCDataChannelConnecting;
  @override
  int get bufferedAmount => buffer;
  @override
  Future<int> getBufferedAmount() async => buffer;
  void open() {
    state = RTCDataChannelState.RTCDataChannelOpen;
    onDataChannelState?.call(state);
  }

  @override
  Future<void> send(RTCDataChannelMessage data) async {
    if (state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('closed');
    }
    final copy = data.isBinary
        ? RTCDataChannelMessage.fromBinary(Uint8List.fromList(data.binary))
        : RTCDataChannelMessage(data.text);
    sent.add(copy);
    scheduleMicrotask(() {
      if (peer?.state == RTCDataChannelState.RTCDataChannelOpen) {
        peer?.onMessage?.call(copy);
      }
    });
  }

  @override
  Future<void> close() async {
    state = RTCDataChannelState.RTCDataChannelClosed;
    onDataChannelState?.call(state);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class WebPeerFakeConnection extends RTCPeerConnection {
  WebPeerFakeConnection(this.fingerprint);
  final String fingerprint;
  final channel = WebPeerFakeChannel();
  RTCSessionDescription? local, remote;
  Map<String, dynamic>? config;
  bool closed = false, disposed = false;
  RTCIceGatheringState gathering =
      RTCIceGatheringState.RTCIceGatheringStateComplete;
  @override
  RTCIceGatheringState get iceGatheringState => gathering;
  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async {
    if (constraints?['mandatory']?['OfferToReceiveAudio'] != false ||
        constraints?['mandatory']?['OfferToReceiveVideo'] != false) {
      throw StateError('Only data channels may be negotiated');
    }
    return RTCSessionDescription(webPeerTestSdp(fingerprint), 'offer');
  }

  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async {
    if (constraints?['mandatory']?['OfferToReceiveAudio'] != false ||
        constraints?['mandatory']?['OfferToReceiveVideo'] != false) {
      throw StateError('Only data channels may be negotiated');
    }
    return RTCSessionDescription(webPeerTestSdp(fingerprint), 'answer');
  }

  @override
  Future<RTCDataChannel> createDataChannel(
    String label,
    RTCDataChannelInit init,
  ) async {
    if (!init.ordered ||
        init.maxRetransmits != -1 ||
        init.maxRetransmitTime != -1) {
      throw StateError('unreliable');
    }
    return channel;
  }

  @override
  Future<void> setLocalDescription(RTCSessionDescription value) async {
    local = value;
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription value) async {
    remote = value;
  }

  @override
  Future<RTCSessionDescription?> getLocalDescription() async => local;
  @override
  Future<RTCSessionDescription?> getRemoteDescription() async => remote;
  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> webPeerUntil(bool Function() predicate) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('fake WebRTC');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
