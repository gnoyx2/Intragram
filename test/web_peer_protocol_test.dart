import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intragram/network/web_peer_protocol.dart';

import 'web_peer_fake.dart';

void main() {
  final bad = throwsA(isA<WebPeerProblem>());
  final id = 'a' * 32;
  String frame(Map<String, dynamic> data) => jsonEncode({'id': id, ...data});
  test(
    'IGW1 code uses exact browser-compatible UTF8 JSON and strict description',
    () {
      final sdp = webPeerTestSdp('AA');
      final code = webPeerEncodeDescription(
        RTCSessionDescription(sdp, 'offer'),
      );
      final browserVector =
          'IGW1.${base64UrlEncode(utf8.encode(jsonEncode({'v': 1, 'type': 'offer', 'sdp': sdp}))).replaceAll('=', '')}';
      expect(code, browserVector);
      expect(webPeerDecodeCode(code, 'offer').sdp, sdp);
      expect(() => webPeerDecodeCode(code, 'answer'), bad);
      for (final invalid in [
        'IGA1.test',
        'IGW1.!',
        'IGW1.${'a' * 50000}',
        'http://192.168.1.1',
      ]) {
        expect(() => webPeerDecodeCode(invalid), bad);
      }
      for (final suffix in [
        'a=fingerprint:sha-256 ${List.filled(32, 'BB').join(':')}\r\n',
        'a=ice-ufrag:evil\r\n',
        'a=ice-pwd:otherabcdefghijklmnopqrstuvw\r\n',
        'a=candidate:9 1 udp 1234 8.8.8.8 4567 typ host\r\n',
        'm=audio 9 UDP/TLS/RTP/SAVPF 0\r\n',
      ]) {
        expect(
          () => webPeerValidateDescription({
            'type': 'offer',
            'sdp': sdp + suffix,
          }, 'offer'),
          bad,
        );
      }
      final filtered = webPeerEncodeDescription(
        RTCSessionDescription(
          '${sdp}a=candidate:2 1 udp 999 8.8.8.8 5555 typ host\r\n',
          'offer',
        ),
      );
      expect(webPeerDecodeCode(filtered).sdp, isNot(contains('8.8.8.8')));
      expect(
        () => webPeerEncodeDescription(
          RTCSessionDescription(
            sdp.replaceAll('192.168.1.2', '8.8.8.8'),
            'offer',
          ),
        ),
        bad,
      );
    },
  );

  test('only literal private/loopback/link-local IPs and mDNS are local', () {
    for (final host in [
      '10.1.2.3',
      '172.16.0.1',
      '172.31.9.9',
      '192.168.1.1',
      '169.254.2.3',
      '127.0.0.1',
      '::1',
      'fd12::1',
      'fc00::1234',
      'fe80::1',
      'a12.local',
    ]) {
      expect(webPeerLocalAddress(host), true, reason: host);
    }
    for (final host in [
      '8.8.8.8',
      '172.15.0.1',
      '172.32.0.1',
      '192.169.0.1',
      '012.0.0.1',
      '10.1.1.999',
      'example.com',
      'localhost',
      '2001:db8::1',
      'fe00::1',
      'fdxx::1',
      '::ffff:192.168.1.1',
    ]) {
      expect(webPeerLocalAddress(host), false, reason: host);
    }
  });

  test(
    'bounded text, file names, metadata and controls reject malformed frames',
    () {
      expect(
        webPeerParseFrame(frame({'kind': 'text', 'text': '한국어'}))['text'],
        '한국어',
      );
      for (final data in [
        {'kind': 'text', 'text': ' '},
        {'kind': 'text', 'text': '가' * 6000},
        {'kind': 'file-offer', 'name': '../x', 'size': 1},
        {'kind': 'file-offer', 'name': 'x', 'size': -1},
        {'kind': 'file-offer', 'name': 'x', 'size': 1.5},
        {'kind': 'file-offer', 'name': 'x', 'size': webPeerMaxFileBytes + 1},
        {
          'kind': 'control',
          'control': {'k': 'read', 'id': 'bad'},
        },
        {
          'kind': 'control',
          'control': {'k': 'verify', 'sas': '123'},
        },
        {
          'kind': 'control',
          'control': {'k': 'react', 'id': id, 'emoji': 'evil', 'on': true},
        },
        {
          'kind': 'control',
          'control': {'k': 'meta', 'id': id, 'ttl': 2},
        },
        {'kind': 'unknown'},
      ]) {
        expect(() => webPeerParseFrame(frame(data)), bad, reason: '$data');
      }
      expect(
        webPeerParseFrame(
          frame({'kind': 'file-offer', 'name': '빈 파일', 'size': 0}),
        )['size'],
        0,
      );
      expect(
        webPeerParseFrame(
          frame({
            'kind': 'control',
            'control': {
              'k': 'meta',
              'id': id,
              'ttl': 5,
              'quote': 'quote',
              'replyTo': id,
            },
          }),
        )['kind'],
        'control',
      );
    },
  );

  test('group controls bound the roster and prohibit nested forwarding', () {
    final self = 'a' * 32, host = 'b' * 32;
    final room = {
      'k': 'room-state',
      'self': self,
      'host': host,
      'members': [
        {'id': self, 'alias': 'guest'},
        {'id': host, 'alias': 'host'},
      ],
    };
    expect(() => webPeerValidateControl(room), returnsNormally);
    expect(
      () => webPeerValidateControl({
        ...room,
        'members': [
          {'id': self, 'alias': 'guest'},
        ],
      }),
      bad,
    );
    expect(
      () => webPeerValidateControl({
        ...room,
        'members': List.filled(10, {'id': self, 'alias': 'x'}),
      }),
      bad,
    );
    expect(
      () => webPeerValidateControl({
        'k': 'room-control',
        'origin': self,
        'control': {'k': 'react', 'id': host, 'emoji': '👍', 'on': true},
      }),
      returnsNormally,
    );
    expect(
      () => webPeerValidateControl({
        'k': 'room-control',
        'origin': self,
        'control': {
          'k': 'room-control',
          'origin': host,
          'control': {'k': 'typing', 'on': true},
        },
      }),
      bad,
    );
    expect(
      () => webPeerValidateControl({
        'k': 'room-control',
        'origin': self,
        'control': {'k': 'verify', 'sas': '123456'},
      }),
      bad,
    );
  });

  test(
    'file chunks roundtrip byte-order and reject over/undersized records',
    () {
      final bytes = Uint8List.fromList(
        List.generate(webPeerChunkBytes, (i) => i % 251),
      );
      final raw = webPeerMakeChunk(id, 32768, bytes);
      final parsed = webPeerParseChunk(raw);
      expect(parsed.id, id);
      expect(parsed.offset, 32768);
      expect(parsed.bytes, bytes);
      expect(raw.sublist(16, 20), [0, 0, 128, 0]);
      expect(() => webPeerParseChunk(Uint8List(20)), bad);
      expect(() => webPeerParseChunk(Uint8List(webPeerChunkBytes + 21)), bad);
      expect(() => webPeerMakeChunk(id, 0, Uint8List(0)), bad);
    },
  );
}
