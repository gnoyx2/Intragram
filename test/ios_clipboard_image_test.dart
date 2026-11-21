import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/os_privacy.dart';

// iOS 클립보드 이미지는 네이티브에서 비동기로 받음: pasteboard 플러그인은 메인 스레드에서 UIPasteboard.image를
// 읽어서, 원본 앱(Universal Clipboard면 Mac)이 늦거나 응답하지 않으면 앱이 멈췄음 (iPhone 시뮬레이터에서 재현)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('intragram/privacy');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('clipboardImage returns the bytes the native side sends', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'clipboardImage'
          ? Uint8List.fromList([1, 2, 3])
          : null,
    );
    expect(await OsPrivacy.clipboardImage(), [1, 2, 3]);
  });

  test('clipboardImage is null when the platform has no handler', () async {
    expect(await OsPrivacy.clipboardImage(), isNull);
  });

  test('iOS reads the clipboard image off the main thread with a limit', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(delegate, contains('case "clipboardImage"'));
    expect(delegate, contains('loadObject(ofClass: UIImage.self)'));
    expect(delegate, isNot(contains('UIPasteboard.general.image')));
    final input = File(
      'lib/features/chat/chat_input/clipboard.dart',
    ).readAsStringSync();
    expect(input, contains('OsPrivacy.clipboardImage()'));
  });
}
