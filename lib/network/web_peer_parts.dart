part of 'web_peer.dart';

final class _PartBuffer {
  _PartBuffer({required this.target, required this.count, required this.total});
  final String target;
  final int count, total;
  int nextIndex = 0;
  int receivedBytes = 0;
  final chunks = BytesBuilder(copy: false);
  Timer? timer;

  void dispose() {
    timer?.cancel();
    timer = null;
    chunks.clear();
  }
}

extension _WebPeerParts on WebPeerSession {
  Future<String> _sendText(
    String text, {
    String? id,
    int maxBytes = webPeerMaxTextBytes,
  }) async {
    final encoded = utf8.encode(text);
    if (text.trim().isEmpty ||
        encoded.length > maxBytes ||
        maxBytes > kFrameCeilingBytes) {
      throw const WebPeerProblem('text-too-large');
    }
    final messageId = id ?? webPeerNewId();
    if (encoded.length <= webPeerMaxTextBytes) {
      final raw = jsonEncode({'kind': 'text', 'id': messageId, 'text': text});
      if (utf8.encode(raw).length <= webPeerMaxTextBytes + 512) {
        webPeerParseFrame(raw);
        await _sendRaw(RTCDataChannelMessage(raw));
        return messageId;
      }
    }
    await _sendParts(messageId, 'text', Uint8List.fromList(encoded));
    return messageId;
  }

  Future<void> _sendControl(Map<String, dynamic> control) async {
    webPeerValidateControl(control, maxTextBytes: kFrameCeilingBytes);
    final controlId = webPeerNewId();
    final singleOk =
        (control['k'] != 'room-msg' ||
            utf8.encode(control['text'] as String).length <=
                webPeerMaxTextBytes) &&
        (control['k'] != 'native-room' ||
            utf8.encode(jsonEncode(control['frame'])).length <= 8192);
    if (singleOk) {
      final raw = jsonEncode({
        'kind': 'control',
        'id': controlId,
        'control': control,
      });
      if (utf8.encode(raw).length <= webPeerMaxTextBytes + 512) {
        webPeerParseFrame(raw);
        await _sendRaw(RTCDataChannelMessage(raw));
        return;
      }
    }
    final payload = Uint8List.fromList(utf8.encode(jsonEncode(control)));
    if (payload.length > webPeerMaxReassembledBytes) {
      throw const WebPeerProblem('invalid-frame');
    }
    await _sendParts(controlId, 'control', payload);
  }

  // 섞여 보내면 받는 쪽의 진행 중 합계·버퍼 4개 상한에 걸려 정상 메시지로도 링크가 끊김 (방 호스트의 동시 중계)
  Future<void> _sendParts(String id, String target, Uint8List payload) {
    final operation = _partsTail.then(
      (_) => _sendPartsInOrder(id, target, payload),
    );
    _partsTail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _sendPartsInOrder(
    String id,
    String target,
    Uint8List payload,
  ) async {
    final count =
        (payload.length + webPeerMaxPartBytes - 1) ~/ webPeerMaxPartBytes;
    if (count < 2) {
      // Payload exceeded single-frame JSON overhead even though raw bytes <= 12 KiB:
      // split in half so count >= 2 invariant holds.
      final mid = payload.length ~/ 2;
      final slices = [
        Uint8List.sublistView(payload, 0, mid),
        Uint8List.sublistView(payload, mid),
      ];
      for (var i = 0; i < slices.length; i++) {
        await _backpressure();
        await _send({
          'kind': 'part',
          'id': id,
          'target': target,
          'index': i,
          'count': 2,
          'total': payload.length,
          'data': base64Encode(slices[i]),
        });
      }
      return;
    }
    for (var i = 0; i < count; i++) {
      await _backpressure();
      final start = i * webPeerMaxPartBytes;
      final end = (start + webPeerMaxPartBytes).clamp(0, payload.length);
      await _send({
        'kind': 'part',
        'id': id,
        'target': target,
        'index': i,
        'count': count,
        'total': payload.length,
        'data': base64Encode(Uint8List.sublistView(payload, start, end)),
      });
    }
  }

  void _receivePart(Map<String, dynamic> frame) {
    final id = frame['id'] as String;
    if (_seen.contains(id)) return;
    final target = frame['target'] as String,
        index = frame['index'] as int,
        count = frame['count'] as int,
        total = frame['total'] as int;
    final chunk = base64Decode(frame['data'] as String);
    final totalHeld = _parts.values.fold<int>(
      0,
      (sum, item) => sum + item.receivedBytes,
    );
    final cap = maxReassembledBytes();
    if (total > cap || totalHeld + chunk.length > cap) {
      throw const WebPeerProblem('invalid-frame');
    }
    _PartBuffer? buffer = _parts[id];
    if (index == 0) {
      if (buffer != null || _parts.length >= 4) {
        throw const WebPeerProblem('invalid-frame');
      }
      buffer = _PartBuffer(target: target, count: count, total: total);
      _parts[id] = buffer;
    } else if (buffer == null ||
        buffer.target != target ||
        buffer.count != count ||
        buffer.total != total ||
        buffer.nextIndex != index) {
      throw const WebPeerProblem('invalid-frame');
    }
    if (buffer.receivedBytes + chunk.length > total) {
      _parts.remove(id)?.dispose();
      throw const WebPeerProblem('invalid-frame');
    }
    buffer.chunks.add(chunk);
    buffer.receivedBytes += chunk.length;
    buffer.nextIndex = index + 1;
    buffer.timer?.cancel();
    buffer.timer = Timer(const Duration(seconds: 30), () {
      _parts.remove(id)?.dispose();
    });
    if (buffer.nextIndex < count) return;
    _parts.remove(id);
    buffer.timer?.cancel();
    if (buffer.receivedBytes != total) {
      buffer.dispose();
      throw const WebPeerProblem('invalid-frame');
    }
    final assembled = buffer.chunks.takeBytes();
    final String decoded;
    try {
      decoded = utf8.decode(assembled);
    } on FormatException {
      throw const WebPeerProblem('invalid-frame');
    }
    if (target == 'text') {
      if (decoded.trim().isEmpty || assembled.length > kFrameCeilingBytes) {
        throw const WebPeerProblem('invalid-frame');
      }
      if (!_remember(id)) return;
      onTextFrame?.call({'id': id, 'text': decoded});
      onMessage?.call(decoded);
      return;
    }
    final dynamic parsed;
    try {
      parsed = jsonDecode(decoded);
    } on Object {
      throw const WebPeerProblem('invalid-frame');
    }
    if (parsed is! Map<String, dynamic>) {
      throw const WebPeerProblem('invalid-frame');
    }
    webPeerValidateControl(parsed, maxTextBytes: kFrameCeilingBytes);
    if (!_remember(id)) return;
    onControl?.call(parsed);
  }

  void _clearParts() {
    for (final buffer in _parts.values) {
      buffer.dispose();
    }
    _parts.clear();
  }
}
