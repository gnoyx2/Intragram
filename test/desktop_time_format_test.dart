import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/desktop_time_format.dart';

void main() {
  test('reads the Windows short time pattern for 12 or 24 hour clocks', () {
    const header = '\r\nHKEY_CURRENT_USER\\Control Panel\\International\r\n';
    expect(
      parseWindowsShortTime('$header    sShortTime    REG_SZ    HH:mm\r\n'),
      isTrue,
    );
    expect(
      parseWindowsShortTime('$header    sShortTime    REG_SZ    tt h:mm\r\n'),
      isFalse,
    );
    expect(parseWindowsShortTime('ERROR: not found'), isNull);
  });

  test('reads the GNOME clock format that Flutter also follows', () {
    expect(parseGnomeClockFormat("'24h'\n"), isTrue);
    expect(parseGnomeClockFormat("'12h'\n"), isFalse);
    expect(parseGnomeClockFormat('No such key'), isNull);
  });
}
