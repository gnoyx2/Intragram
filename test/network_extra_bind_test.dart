import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/network_guard.dart';

void main() {
  // 유선·Wi-Fi가 같은 망이면 mDNS가 두 주소를 다 광고함: 다른 물리 NIC 주소도 받아야 광고된 주소로 붙음
  test('the other physical NIC address is bound too, never VPN or VM ones', () {
    final extra = NetworkGuard.pickExtraBindAddresses([
      ('이더넷', InternetAddress('172.30.1.32')),
      ('Wi-Fi', InternetAddress('172.30.1.58')),
      ('vEthernet (WSL)', InternetAddress('172.25.192.1')),
      ('NordLynx', InternetAddress('10.5.0.2')),
      ('Wi-Fi 2', InternetAddress('169.254.10.10')),
    ], InternetAddress('172.30.1.32')).map((a) => a.address);
    expect(extra, ['172.30.1.58']);
  });
}
