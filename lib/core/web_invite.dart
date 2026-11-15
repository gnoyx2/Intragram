import 'dart:convert';

// 인코딩은 암호화가 아님: 기존 포털 토큰이 든 코드를 민감한 클립보드로만 복사함.
String encodeWebInvite(String portalUrl) =>
    'IGA1.${base64Url.encode(utf8.encode(portalUrl)).replaceAll('=', '')}';
