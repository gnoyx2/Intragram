import 'dart:convert';

import 'package:cryptography/cryptography.dart';

// 게스트 포털 한 장짜리 HTML과 인라인 블록 CSP 해시.
// 브라우저는 HTML을 읽을 때 CRLF·CR을 LF로 바꾼 뒤 해시를 비교함: Windows 체크아웃은 자산이 CRLF로 올 수 있어 먼저 맞춤
Future<({String html, List<String> directives})> buildPortalPage({
  required String shell,
  required String css,
  required String js,
}) async {
  final html = shell
      .replaceFirst('/*__APP_CSS__*/', css)
      .replaceFirst('/*__APP_JS__*/', js)
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final directives = <String>[];
  for (final tag in ['script', 'style']) {
    final hashes = <String>[];
    for (final match in RegExp('<$tag>([\\s\\S]*?)</$tag>').allMatches(html)) {
      final hash = await Sha256().hash(utf8.encode(match.group(1)!));
      hashes.add("'sha256-${base64Encode(hash.bytes)}'");
    }
    directives.add("$tag-src ${hashes.join(' ')}");
  }
  return (html: html, directives: directives);
}
