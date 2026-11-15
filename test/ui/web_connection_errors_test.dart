import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/features/portal/web_connection_dialog.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/widgets/picker_feedback.dart';

import '_harness.dart';

class _FailedOffer extends WebPeerSession {
  _FailedOffer(this.code);
  final String code;
  @override
  Future<String> createOffer() async => throw WebPeerProblem(code);
}

void main() {
  late AppIdentity identity;
  setUpAll(() async => identity = await AppIdentity.create());

  for (final (code, expected) in [
    (
      'invalid-code',
      'Enter a valid complete IGW1 invitation or response code.',
    ),
    (
      'private-implementation-detail',
      'Could not complete the action. Check the connection and file, then try again.',
    ),
  ]) {
    testWidgets('connection error $code shows translated text', (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final h = Harness(
        registryBuilder: (store, _) => LinkRegistry(
          store: store,
          crypto: CryptoEngine(),
          identity: identity,
        ),
      );
      addTearDown(h.dispose);
      h.registry.debugWebSessionFactory =
          ({onState, onTextFrame, onControl, onTransfer, onError}) =>
              _FailedOffer(code);
      await tester.pumpWidget(
        h.wrap(const Scaffold(body: WebConnectionDialog())),
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Create invitation code'),
      );
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);
      expect(find.textContaining('secureWeb.error.'), findsNothing);
      expect(find.text(code), findsNothing);
      expect(h.store.conversations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  // 상한을 넘어 빠진 파일은 조용히 사라지지 않고 안내가 뜸
  testWidgets('a file left out for the size limit shows a notice', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(
      h.wrap(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: fileTooLargeNotice(context),
              child: const Text('too large'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('too large'));
    await tester.pump();
    expect(
      find.text(
        'Files over 64 GiB cannot be sent over an encrypted web '
        'connection, so they were left out.',
      ),
      findsOneWidget,
    );
  });
}
