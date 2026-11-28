import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

// 서버는 떠도 Windows 방화벽이 들어오는 연결을 막을 수 있음 (첫 경고 창에서 취소, 공용에서만 허용한 뒤 망이 개인으로 바뀜).
// 이 실행 파일의 켜진 인바운드 규칙과 지금 망 종류를 PowerShell로 읽음. 못 읽으면 null이라 알리지 않음
Future<bool?> windowsInboundBlocked() async {
  if (!Platform.isWindows || Platform.environment['FLUTTER_TEST'] == 'true') {
    return null;
  }
  final exe = Platform.resolvedExecutable.replaceAll("'", "''");
  try {
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r"$ErrorActionPreference='SilentlyContinue';"
          r"Get-NetConnectionProfile | ForEach-Object { 'net=' + $_.NetworkCategory };"
          r"Get-NetFirewallProfile | ForEach-Object { 'fw=' + $_.Name + '=' + $_.Enabled };"
          "Get-NetFirewallApplicationFilter -Program '$exe' | Get-NetFirewallRule | "
          r"Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' } | "
          r"ForEach-Object { 'rule=' + $_.Action + '=' + $_.Profile }",
    ]);
    if (result.exitCode != 0) return null;
    return parseFirewallReport(result.stdout as String);
  } on Object {
    return null;
  }
}

// 망 하나라도 방화벽이 켜져 있고 차단 규칙이 있거나 허용 규칙이 없으면 그 망의 상대는 못 붙음 (Windows는 규칙 없는 인바운드를 막음)
@visibleForTesting
bool? parseFirewallReport(String report) {
  final networks = <String>{}, allow = <String>[], block = <String>[];
  final enabled = <String, bool>{};
  for (final line in report.split('\n')) {
    switch (line.trim().split('=')) {
      case ['net', final category]:
        networks.add(category == 'DomainAuthenticated' ? 'Domain' : category);
      case ['fw', final name, final on]:
        enabled[name] = on == 'True';
      case ['rule', 'Allow', final profile]:
        allow.add(profile);
      case ['rule', 'Block', final profile]:
        block.add(profile);
    }
  }
  if (networks.isEmpty) return null;
  bool covers(String profile, String network) =>
      profile == 'Any' || profile.split(', ').contains(network);
  return networks.any(
    (network) =>
        enabled[network] != false &&
        (block.any((p) => covers(p, network)) ||
            !allow.any((p) => covers(p, network))),
  );
}
