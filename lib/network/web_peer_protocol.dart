import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'room_integrity/author_event.dart';
import 'package:intragram/audit/attestation.dart';
import 'package:intragram/core/constants.dart'
    show kFrameCeilingBytes, kMaxConcurrentTransfers, kMaxWebGuests;
import 'package:intragram/network/org_auth.dart';
import 'package:intragram/network/protocol.dart'
    show wireBytes, wireId, wireInt;

part 'web_peer_frames.dart';
part 'web_peer_native_room.dart';

const webPeerMaxFileBytes = 100 * 1024 * 1024;
const webPeerMaxStreamFileBytes = 64 * 1024 * 1024 * 1024;
const webPeerMaxTextBytes = 16 * 1024;
const webPeerMaxPartBytes = 12 * 1024;
const webPeerMaxReassembledBytes = kFrameCeilingBytes * 2 + 8192;
const webPeerMaxNativeRoomBytes = kFrameCeilingBytes * 2 + 4096;
const webPeerMaxRoomMembers = kMaxWebGuests;
const webPeerChunkBytes = 16 * 1024;
const webPeerStreamChunkBytes = 64 * 1024;
const webPeerMaxCodeChars = 48 * 1024;
// 한 방향에 한꺼번에 걸어 둘 수 있는 파일 제안 수 (묶음 하나의 상한)
const webPeerMaxWaitingOffers = 32;
// 방향마다 동시에 바이트가 흐르는 파일 수 (v7 TransferConcurrencyGate와 같은 값). 상대가 capabilities로
// 알린 값과 작은 쪽을 씀. 알리지 않은 상대(보조 HTML 클라이언트)는 1이라 예전처럼 한 파일씩 흐름.
// lanes를 알린 상대는 file-queued(수락했지만 받는 쪽 자리가 없어 기다림)도 앎
const webPeerLanes = kMaxConcurrentTransfers;
const webPeerMaxLanes = 8;
// 연결되면 앱·Flutter 웹이 서로 알리는 기능 (보조 HTML 클라이언트는 보내지 않음)
const webPeerCapabilities = {
  'k': 'capabilities',
  'v': 1,
  'batch': true,
  'lanes': webPeerLanes,
};
final _idPattern = RegExp(r'^[a-f0-9]{32}$');
final _random = Random.secure();

final class WebPeerProblem implements Exception {
  const WebPeerProblem(this.code);
  final String code;
  @override
  String toString() => code;
}

String webPeerNewId() => List.generate(
  16,
  (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

bool webPeerLocalAddress(String host) {
  if (host.length <= 253 &&
      RegExp(
        r'^[a-z0-9-]+(?:\.[a-z0-9-]+)*\.local$',
        caseSensitive: false,
      ).hasMatch(host)) {
    return true;
  }
  if (host.contains(':')) {
    final List<int> bytes;
    try {
      bytes = Uri.parseIPv6Address(host);
    } on FormatException {
      return false;
    }
    final loopback =
        bytes.take(15).every((byte) => byte == 0) && bytes[15] == 1;
    return loopback ||
        bytes[0] & 0xfe == 0xfc ||
        (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80);
  }
  final parts = host.split('.');
  if (parts.length != 4 ||
      parts.any(
        (p) => !RegExp(r'^(0|[1-9]\d{0,2})$').hasMatch(p) || int.parse(p) > 255,
      )) {
    return false;
  }
  final a = int.parse(parts[0]);
  final b = int.parse(parts[1]);
  return a == 10 ||
      a == 127 ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168) ||
      (a == 169 && b == 254);
}

bool _validCandidate(String line) {
  final p = line.trim().split(RegExp(r'\s+'));
  if (p.length < 8) return false;
  final port = int.tryParse(p[5]);
  return RegExp(r'^a=candidate:[\w+/.-]+$').hasMatch(p[0]) &&
      p[1] == '1' &&
      ['udp', 'tcp'].contains(p[2].toLowerCase()) &&
      RegExp(r'^\d+$').hasMatch(p[3]) &&
      webPeerLocalAddress(p[4]) &&
      RegExp(r'^\d+$').hasMatch(p[5]) &&
      port != null &&
      port > 0 &&
      port <= 65535 &&
      p[6] == 'typ' &&
      p[7] == 'host' &&
      !p.contains('raddr') &&
      !p.contains('rport');
}

RTCSessionDescription webPeerValidateDescription(
  Map<String, dynamic> value,
  String expectedType,
) {
  final sdp = value['sdp'];
  if (value['type'] != expectedType ||
      !['offer', 'answer'].contains(expectedType) ||
      sdp is! String ||
      sdp.length > 32000 ||
      RegExp(r'[^\x09\x0a\x0d\x20-\x7e]').hasMatch(sdp)) {
    throw const WebPeerProblem('invalid-code');
  }
  final lines = sdp.trim().split(RegExp(r'\r?\n'));
  final media = lines.where((l) => l.startsWith('m=')).toList();
  final candidates = lines.where((l) => l.startsWith('a=candidate:')).toList();
  final fingerprints = lines
      .where((l) => l.toLowerCase().startsWith('a=fingerprint:'))
      .toList();
  bool has(String pattern) =>
      lines.any(RegExp(pattern, caseSensitive: false).hasMatch);
  int count(String prefix) =>
      lines.where((l) => l.toLowerCase().startsWith(prefix)).length;
  if (lines.first != 'v=0' ||
      media.length != 1 ||
      lines.any((l) => !RegExp(r'^[a-z]=').hasMatch(l)) ||
      !RegExp(
        r'^m=application \d+ UDP/DTLS/SCTP webrtc-datachannel$',
      ).hasMatch(media.single) ||
      fingerprints.length != 1 ||
      !RegExp(
        r'^a=fingerprint:sha-256 (?:[a-f\d]{2}:){31}[a-f\d]{2}$',
        caseSensitive: false,
      ).hasMatch(fingerprints.single) ||
      count('a=ice-ufrag:') != 1 ||
      count('a=ice-pwd:') != 1 ||
      !has(r'^a=ice-ufrag:[a-z\d+/]{4,256}$') ||
      !has(r'^a=ice-pwd:[a-z\d+/]{22,256}$') ||
      candidates.isEmpty ||
      candidates.any((l) => !_validCandidate(l)) ||
      lines.any(
        (l) => RegExp(r'^a=(?:remote-candidates|ice-lite)').hasMatch(l),
      )) {
    throw const WebPeerProblem('invalid-code');
  }
  return RTCSessionDescription(sdp, expectedType);
}

String webPeerEncodeDescription(RTCSessionDescription description) {
  final sdp = (description.sdp ?? '')
      .split(RegExp(r'\r?\n'))
      .where((l) => !l.startsWith('a=candidate:') || _validCandidate(l))
      .join('\r\n');
  final clean = webPeerValidateDescription({
    'type': description.type,
    'sdp': sdp,
  }, description.type ?? '');
  final code =
      'IGW1.${base64UrlEncode(utf8.encode(jsonEncode({'v': 1, 'type': clean.type, 'sdp': clean.sdp}))).replaceAll('=', '')}';
  if (code.length > webPeerMaxCodeChars) {
    throw const WebPeerProblem('invalid-code');
  }
  return code;
}

RTCSessionDescription webPeerDecodeCode(String raw, [String? expectedType]) {
  if (raw.length > webPeerMaxCodeChars) {
    throw const WebPeerProblem('invalid-code');
  }
  final code = raw.trim();
  if (!RegExp(r'^IGW1\.[a-z\d_-]+$', caseSensitive: false).hasMatch(code)) {
    throw const WebPeerProblem('invalid-code');
  }
  try {
    final value = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(code.substring(5)))),
    );
    if (value is! Map<String, dynamic> || value['v'] != 1) {
      throw const WebPeerProblem('invalid-code');
    }
    return webPeerValidateDescription(
      value,
      expectedType ?? value['type'] as String,
    );
  } on WebPeerProblem {
    rethrow;
  } on Object {
    throw const WebPeerProblem('invalid-code');
  }
}
