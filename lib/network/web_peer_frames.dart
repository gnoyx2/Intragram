part of 'web_peer_protocol.dart';

void webPeerValidateControl(
  Map<String, dynamic> control, {
  bool room = true,
  int maxTextBytes = webPeerMaxTextBytes,
}) {
  bool id(dynamic value) => value is String && _idPattern.hasMatch(value);
  bool alias(dynamic value) =>
      value is String &&
      value.trim().isNotEmpty &&
      value.length <= 80 &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);
  bool roomMembers(dynamic value) {
    if (value is! List ||
        value.isEmpty ||
        value.length > webPeerMaxRoomMembers) {
      return false;
    }
    final ids = <String>{};
    for (final member in value) {
      if (member is! Map ||
          !id(member['id']) ||
          !alias(member['alias']) ||
          !ids.add(member['id'])) {
        return false;
      }
    }
    return ids.contains(control['self']) && ids.contains(control['host']);
  }

  bool nested(dynamic value) {
    if (value is! Map<String, dynamic> ||
        ![
          'meta',
          'read',
          'burn',
          'react',
          'typing',
          'rename',
          'receipt',
        ].contains(value['k'])) {
      return false;
    }
    try {
      webPeerValidateControl(value, room: false);
      return true;
    } on WebPeerProblem {
      return false;
    }
  }

  final valid = switch (control['k']) {
    'native-room' => webPeerNativeRoom(control, maxTextBytes: maxTextBytes),
    'typing' => control['on'] is bool,
    'read' || 'burn' || 'receipt' => id(control['id']),
    'react' =>
      id(control['id']) &&
          control['on'] is bool &&
          ['👍', '❤️', '😂', '😮', '😢', '🙏'].contains(control['emoji']),
    'rename' => alias(control['alias']),
    'meta' =>
      id(control['id']) &&
          [0, 5, 10, 30, 60, 300, 3600, 86400].contains(control['ttl']) &&
          (control['replyTo'] == null || id(control['replyTo'])) &&
          (control['quote'] == null ||
              control['quote'] is String &&
                  (control['quote'] as String).length <= 500),
    'verify' =>
      control['sas'] is String && RegExp(r'^\d{6}$').hasMatch(control['sas']),
    'identity' =>
      wireBytes(control['pk'], length: 32) != null &&
          wireBytes(control['sg'], length: 64) != null,
    'attestation' => SignedAttestation.fromWire(control['value']) != null,
    'org-credential' =>
      control['credential'] == null ||
          OrgCredential.fromWire(control['credential']) != null &&
              wireBytes(control['credentialDigest'], length: 32) != null &&
              control['policy'] == control['credential']['pol'] &&
              wireBytes(control['pop'], length: 64) != null,
    'room-state' =>
      room &&
          id(control['self']) &&
          id(control['host']) &&
          roomMembers(control['members']),
    'room-msg' =>
      room &&
          id(control['id']) &&
          id(control['origin']) &&
          alias(control['alias']) &&
          control['text'] is String &&
          (control['text'] as String).trim().isNotEmpty &&
          utf8.encode(control['text']).length <= maxTextBytes,
    'room-control' =>
      room && id(control['origin']) && nested(control['control']),
    _ => false,
  };
  if (!valid) {
    throw const WebPeerProblem('invalid-frame');
  }
}

Map<String, dynamic> webPeerParseFrame(String raw) {
  if (utf8.encode(raw).length > webPeerMaxTextBytes + 512) {
    throw const WebPeerProblem('invalid-frame');
  }
  dynamic value;
  try {
    value = jsonDecode(raw);
  } on Object {
    throw const WebPeerProblem('invalid-frame');
  }
  if (value is! Map<String, dynamic> ||
      value['id'] is! String ||
      !_idPattern.hasMatch(value['id']) ||
      value['kind'] is! String) {
    throw const WebPeerProblem('invalid-frame');
  }
  switch (value['kind']) {
    case 'text':
      final text = value['text'];
      if (text is! String ||
          text.trim().isEmpty ||
          utf8.encode(text).length > webPeerMaxTextBytes) {
        throw const WebPeerProblem('invalid-frame');
      }
    case 'file-offer':
      final name = value['name'];
      final size = value['size'];
      final stream = value['stream'];
      final maxSize = stream == true
          ? webPeerMaxStreamFileBytes
          : webPeerMaxFileBytes;
      if (name is! String ||
          name.isEmpty ||
          name.length > 255 ||
          RegExp(r'[\x00-\x1f\x7f/\\]').hasMatch(name) ||
          stream != null && stream is! bool ||
          size is! int ||
          size < 0 ||
          size > maxSize ||
          value['origin'] != null &&
              (value['origin'] is! String ||
                  !_idPattern.hasMatch(value['origin'])) ||
          value['bid'] != null &&
              (value['bid'] is! String || !_idPattern.hasMatch(value['bid'])) ||
          value['alias'] != null &&
              (value['alias'] is! String ||
                  (value['alias'] as String).trim().isEmpty ||
                  (value['alias'] as String).length > 80 ||
                  RegExp(r'[\x00-\x1f\x7f]').hasMatch(value['alias']))) {
        throw const WebPeerProblem('invalid-frame');
      }
    case 'control':
      final control = value['control'];
      if (control is! Map<String, dynamic>) {
        throw const WebPeerProblem('invalid-frame');
      }
      webPeerValidateControl(control);
    case 'part':
      if (!webPeerValidPart(value)) {
        throw const WebPeerProblem('invalid-frame');
      }
    case 'file-accept':
      if (value['stream'] != null && value['stream'] is! bool) {
        throw const WebPeerProblem('invalid-frame');
      }
    case 'file-credit':
      final offset = value['offset'];
      if (offset is! int || offset < 0 || offset > webPeerMaxStreamFileBytes) {
        throw const WebPeerProblem('invalid-frame');
      }
    case 'file-reject' ||
        'file-cancel' ||
        'file-end' ||
        'file-done' ||
        'file-queued':
      break;
    default:
      throw const WebPeerProblem('invalid-frame');
  }
  return value;
}

Uint8List webPeerMakeChunk(String id, int offset, Uint8List bytes) {
  if (!_idPattern.hasMatch(id) ||
      offset < 0 ||
      offset > 0xffffffff ||
      bytes.isEmpty ||
      bytes.length > webPeerChunkBytes) {
    throw const WebPeerProblem('invalid-frame');
  }
  final result = Uint8List(20 + bytes.length);
  for (var i = 0; i < 16; i++) {
    result[i] = int.parse(id.substring(i * 2, i * 2 + 2), radix: 16);
  }
  ByteData.sublistView(result).setUint32(16, offset);
  result.setRange(20, result.length, bytes);
  return result;
}

({String id, int offset, Uint8List bytes}) webPeerParseChunk(Uint8List bytes) {
  if (bytes.length <= 20 || bytes.length > webPeerChunkBytes + 20) {
    throw const WebPeerProblem('invalid-frame');
  }
  return (
    id: bytes.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    offset: ByteData.sublistView(bytes).getUint32(16),
    bytes: Uint8List.sublistView(bytes, 20),
  );
}
