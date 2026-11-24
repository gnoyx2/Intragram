import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/registry/incoming_path_resolver.dart';
import 'package:intragram/network/web_peer_protocol.dart';
import 'package:intragram/widgets/picker_feedback.dart';

void main() {
  testWidgets('a missing file dialog says why instead of doing nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => acceptWithPicker(
                context,
                () async => throw const PickerUnavailableException('no portal'),
              ),
              child: const Text('accept'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('accept'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('xdg-desktop-portal'), findsOneWidget);
  });

  // 웹(OPFS 없는 브라우저)은 받은 파일을 RAM에 100 MiB·100개까지만 둠: 넘으면 수락이 거절되는데,
  // 아무 표시 없이 끝나면 수락 버튼이 고장 난 것처럼 보임
  testWidgets('a full receive budget explains how to make room', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => acceptWithPicker(
                context,
                () async => throw const WebPeerProblem('receive-budget'),
              ),
              child: const Text('accept'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('accept'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('100 MiB'), findsOneWidget);
  });
}
