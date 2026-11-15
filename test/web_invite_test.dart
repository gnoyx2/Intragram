import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/web_invite.dart';
import 'package:intragram/network/server_controller.dart';

void main() {
  test('web invitation round-trips the exact portal URL and padded token', () {
    const token = 'Abc_def-0123456789012345678901234567890123456=';
    const state = ServerState(
      running: true,
      host: '192.168.0.5',
      port: 7890,
      portalEnabled: true,
      portalToken: token,
    );
    final url = state.portalUrl!;
    final invite = encodeWebInvite(url);
    expect(invite, startsWith('IGA1.'));
    expect(invite.substring(5), matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    final decoded = utf8.decode(base64Url.decode(invite.substring(5)));
    expect(decoded, url);
    expect(decoded, endsWith('#t=$token'));
    expect(encodeWebInvite(url), invite);
  });

  test('web invitation also preserves a bracketed local IPv6 host', () {
    const url = 'http://[fd12::1]:7890#t=a_b-c=';
    expect(
      utf8.decode(base64Url.decode(encodeWebInvite(url).substring(5))),
      url,
    );
  });

  test('no portal URL is available to copy before enabling the portal', () {
    for (final state in [
      const ServerState(),
      const ServerState(running: true, host: '192.168.0.5', port: 7890),
      const ServerState(
        running: false,
        host: '192.168.0.5',
        port: 7890,
        portalToken: 'revoked',
      ),
    ]) {
      expect(state.portalUrl, isNull);
    }
  });
}
