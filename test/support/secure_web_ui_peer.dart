import 'dart:typed_data';

import 'package:intragram/network/web_peer.dart';
import 'package:intragram/network/web_peer_protocol.dart'
    show webPeerMaxTextBytes;
import 'package:intragram/network/web_stream_io.dart' show WebReceiveSink;

class SecureWebUiPeer extends WebPeerSession {
  SecureWebUiPeer({
    super.onState,
    super.onTextFrame,
    super.onControl,
    super.onTransfer,
    super.onError,
  });
  final controls = <Map<String, dynamic>>[];
  final texts = <String>[];
  final accepted = <String>[];
  int closeCount = 0;

  void connect() {
    state = 'connected';
    verificationCode = '123456';
    sessionBinding = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    onState?.call(state);
  }

  void text(String id, String text) =>
      onTextFrame?.call({'id': id, 'text': text});
  void control(Map<String, dynamic> control) => onControl?.call(control);
  void file(
    String id,
    int size, {
    String state = 'offered',
    Uint8List? bytes,
  }) => onTransfer?.call(
    WebPeerTransfer(
      id: id,
      name: '$id.bin',
      direction: 'receive',
      state: state,
      size: size,
      transferred: bytes?.length ?? 0,
      bytes: bytes,
    ),
  );

  @override
  Future<String> createOffer() async {
    state = 'waiting';
    onState?.call(state);
    return 'IGW1.test-invitation';
  }

  @override
  Future<void> acceptAnswer(String code) async => connect();
  @override
  Future<void> sendControl(Map<String, dynamic> control) async =>
      controls.add(control);
  @override
  Future<String> sendText(
    String text, {
    String? id,
    int maxBytes = webPeerMaxTextBytes,
  }) async {
    texts.add(text);
    return id ?? 'a' * 32;
  }

  @override
  Future<void> acceptFile(String id) async => accepted.add(id);
  @override
  Future<void> acceptFileStream(
    String id,
    WebReceiveSink sink, {
    bool Function()? wanted,
  }) async {
    await sink.abort();
    accepted.add(id);
  }

  @override
  Future<void> close() async {
    closeCount++;
    state = 'closed';
    onState?.call(state);
  }
}
