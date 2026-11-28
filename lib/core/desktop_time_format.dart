import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

// Windows·Linux 엔진은 실행 중 바뀐 12/24시간 설정을 다시 안 보냄: 앱이 앞으로 올 때 OS 설정을 직접 읽음.
// Windows는 시계 형식이 사는 레지스트리 값, Linux는 Flutter가 읽는 GNOME 키와 같은 값. null이면 엔진 값을 그대로 씀
Future<bool?> desktop24HourFormat() async {
  try {
    if (Platform.isWindows) {
      final result = await Process.run('reg', [
        'query',
        r'HKCU\Control Panel\International',
        '/v',
        'sShortTime',
      ]);
      if (result.exitCode != 0) return null;
      return parseWindowsShortTime(result.stdout as String);
    }
    if (Platform.isLinux) {
      final result = await Process.run('gsettings', [
        'get',
        'org.gnome.desktop.interface',
        'clock-format',
      ]);
      if (result.exitCode != 0) return null;
      return parseGnomeClockFormat(result.stdout as String);
    }
  } on Object {
    return null;
  }
  return null;
}

// 'HH:mm'처럼 대문자 H가 있으면 24시간, 'tt h:mm'이면 12시간
@visibleForTesting
bool? parseWindowsShortTime(String output) {
  final pattern = RegExp(
    r'sShortTime\s+REG_SZ\s+(.+)',
  ).firstMatch(output)?.group(1)?.trim();
  return pattern == null || pattern.isEmpty ? null : pattern.contains('H');
}

@visibleForTesting
bool? parseGnomeClockFormat(String output) => switch (output.trim()) {
  "'24h'" => true,
  "'12h'" => false,
  _ => null,
};
