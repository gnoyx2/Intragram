part of 'web_peer_protocol.dart';

const _nativeMsgKeys = {
  'k',
  'id',
  'text',
  'ttl',
  'ts',
  're',
  ...roomAuthorKeys,
};

bool webPeerNativeRoom(
  Map<String, dynamic> control, {
  int maxTextBytes = webPeerMaxTextBytes,
}) {
  final frame = control['frame'];
  final maxFrameBytes = maxTextBytes <= webPeerMaxTextBytes
      ? 8192
      : webPeerMaxNativeRoomBytes;
  if (frame is! Map<String, dynamic> ||
      utf8.encode(jsonEncode(frame)).length > maxFrameBytes) {
    return false;
  }
  if (control['origin'] != null &&
      (control['origin'] is! String ||
          !_idPattern.hasMatch(control['origin']))) {
    return false;
  }
  if (control['alias'] != null &&
      (control['alias'] is! String ||
          (control['alias'] as String).trim().isEmpty ||
          (control['alias'] as String).length > 80 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(control['alias']))) {
    return false;
  }
  if (frame['k'] == 'capabilities') {
    return frame['v'] == 1 &&
        (frame['batch'] == null || frame['batch'] is bool) &&
        (frame['lanes'] == null ||
            wireInt(frame['lanes'], min: 1, max: webPeerMaxLanes) != null);
  }
  final host = control['host'];
  if (host is! String || !_idPattern.hasMatch(host)) return false;
  if (frame['k'] == 'room_state') {
    final authors = frame['origins'];
    final peers = frame['peers'];
    return wireId(frame['roomIntegrityId']) != null &&
        wireInt(frame['checkpointNo'], min: 0, max: 9007199254740991) != null &&
        wireBytes(frame['merkleRoot'], length: 32) != null &&
        peers is List &&
        peers.isNotEmpty &&
        peers.length <= webPeerMaxRoomMembers &&
        peers.toSet().length == peers.length &&
        peers.contains(host) &&
        peers.every((id) => id is String && _idPattern.hasMatch(id)) &&
        authors is Map<String, dynamic> &&
        authors.isNotEmpty &&
        authors.length <= webPeerMaxRoomMembers &&
        authors.keys.every(_idPattern.hasMatch) &&
        authors.values.every(peers.contains);
  }
  if (frame['k'] != 'msg' ||
      !frame.keys.every(_nativeMsgKeys.contains) ||
      frame['id'] is! String ||
      !_idPattern.hasMatch(frame['id']) ||
      frame['text'] is! String ||
      (frame['text'] as String).trim().isEmpty ||
      utf8.encode(frame['text'] as String).length > maxTextBytes ||
      wireInt(frame['ttl'], min: 0, max: 86400) == null ||
      wireInt(frame['ts'], min: 0, max: 9007199254740991) == null ||
      frame['re'] != null &&
          (frame['re'] is! String || !_idPattern.hasMatch(frame['re']))) {
    return false;
  }
  return RoomAuthorEvent.fromWire(frame, hostPeerId: host) != null;
}

const _maxPartCount = (webPeerMaxReassembledBytes ~/ webPeerMaxPartBytes) + 2;

bool webPeerValidPart(Map<String, dynamic> value) {
  final target = value['target'],
      index = value['index'],
      count = value['count'],
      total = value['total'],
      data = value['data'];
  if (!['text', 'control'].contains(target) ||
      index is! int ||
      count is! int ||
      total is! int ||
      count < 2 ||
      count > _maxPartCount ||
      index < 0 ||
      index >= count ||
      total <= 0 ||
      total > webPeerMaxReassembledBytes ||
      data is! String ||
      data.isEmpty ||
      data.length > 16384 ||
      !RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(data)) {
    return false;
  }
  final Uint8List decoded;
  try {
    decoded = base64Decode(data);
  } on FormatException {
    return false;
  }
  return decoded.isNotEmpty &&
      decoded.length <= webPeerMaxPartBytes &&
      decoded.length <= total;
}

const _u32Base = 0x100000000;

Uint8List webPeerMakeStreamChunk(String id, int offset, Uint8List bytes) {
  if (!_idPattern.hasMatch(id) ||
      offset < 0 ||
      offset > webPeerMaxStreamFileBytes ||
      bytes.isEmpty ||
      bytes.length > webPeerStreamChunkBytes) {
    throw const WebPeerProblem('invalid-frame');
  }
  final result = Uint8List(24 + bytes.length);
  for (var i = 0; i < 16; i++) {
    result[i] = int.parse(id.substring(i * 2, i * 2 + 2), radix: 16);
  }
  final header = ByteData.sublistView(result);
  header.setUint32(16, offset ~/ _u32Base);
  header.setUint32(20, offset.remainder(_u32Base));
  result.setRange(24, result.length, bytes);
  return result;
}

({String id, int offset, Uint8List bytes}) webPeerParseStreamChunk(
  Uint8List bytes,
) {
  if (bytes.length <= 24 || bytes.length > webPeerStreamChunkBytes + 24) {
    throw const WebPeerProblem('invalid-frame');
  }
  final header = ByteData.sublistView(bytes);
  final offset = header.getUint32(16) * _u32Base + header.getUint32(20);
  if (offset > webPeerMaxStreamFileBytes) {
    throw const WebPeerProblem('invalid-frame');
  }
  return (
    id: bytes.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    offset: offset,
    bytes: Uint8List.sublistView(bytes, 24),
  );
}
