import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/windows_firewall.dart';

void main() {
  const profiles = 'fw=Domain=True\r\nfw=Private=True\r\nfw=Public=True\r\n';

  test('an allow rule for the current network means peers can connect', () {
    expect(
      parseFirewallReport('net=Public\r\n${profiles}rule=Allow=Public\r\n'),
      isFalse,
    );
    expect(
      parseFirewallReport('net=Private\r\n${profiles}rule=Allow=Any\r\n'),
      isFalse,
    );
  });

  test('cancelling the firewall prompt leaves a block rule', () {
    expect(
      parseFirewallReport(
        'net=Public\r\n${profiles}rule=Block=Public\r\nrule=Allow=Public\r\n',
      ),
      isTrue,
    );
  });

  test(
    'a network that turned private with only a public allow rule is blocked',
    () {
      expect(
        parseFirewallReport('net=Private\r\n${profiles}rule=Allow=Public\r\n'),
        isTrue,
      );
    },
  );

  test('a firewall switched off for the network never warns', () {
    expect(parseFirewallReport('net=Private\r\nfw=Private=False\r\n'), isFalse);
  });

  test('an unreadable report stays silent', () {
    expect(parseFirewallReport(''), isNull);
  });
}
