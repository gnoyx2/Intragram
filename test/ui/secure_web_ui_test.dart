import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/features/chat/chat_input.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/portal/web_connection_dialog.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';

import '../support/secure_web_ui_peer.dart';
import '_harness.dart';

void main() {
  late AppIdentity identity;
  setUpAll(() async => identity = await AppIdentity.create());

  Future<({Harness harness, List<SecureWebUiPeer> peers})> open(
    WidgetTester tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final h = Harness(
      registryBuilder: (store, _) => LinkRegistry(
        store: store,
        crypto: CryptoEngine(),
        identity: identity,
      ),
    );
    addTearDown(h.dispose);
    final peers = <SecureWebUiPeer>[];
    h.registry.debugWebSessionFactory =
        ({onState, onTextFrame, onControl, onTransfer, onError}) {
          final peer = SecureWebUiPeer(
            onState: onState,
            onTextFrame: onTextFrame,
            onControl: onControl,
            onTransfer: onTransfer,
            onError: onError,
          );
          peers.add(peer);
          return peer;
        };
    await tester.pumpWidget(
      h.wrap(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showWebConnectionDialog(context),
              child: const Text('Open encrypted connection'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open encrypted connection'));
    await tester.pumpAndSettle();
    return (harness: h, peers: peers);
  }

  testWidgets(
    'code exchange opens the shared chat, composer and file consent',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rig = await open(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Create invitation code'),
      );
      await tester.pumpAndSettle();
      final local = tester.widget<TextField>(
        find.byKey(const Key('shared-web-local-code')),
      );
      expect(local.controller!.text, 'IGW1.test-invitation');
      await tester.enterText(
        find.byKey(const Key('shared-web-remote-code')),
        'IGW1.response',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatRoomScreen), findsOneWidget);
      expect(find.byType(ChatInput), findsOneWidget);
      expect(find.byType(WebConnectionDialog), findsNothing);
      final peer = rig.peers.single;
      peer.text('b' * 32, '<safe> incoming 한글');
      expect(
        rig.harness.store.messageById('b' * 32)?.text,
        '<safe> incoming 한글',
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.semanticsLabel == '<safe> incoming 한글',
        ),
        findsOneWidget,
      );
      expect(peer.controls.any((c) => c['k'] == 'read'), isTrue);
      await tester.enterText(find.byType(TextField), 'shared composer reply');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(peer.texts, contains('shared composer reply'));
      peer.file('c' * 32, 1);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept'));
      await tester.pump();
      expect(peer.accepted, ['c' * 32]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('cancelled invitation closes its link and leaves no draft chat', (
    tester,
  ) async {
    final rig = await open(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Create invitation code'),
    );
    await tester.pumpAndSettle();
    expect(rig.harness.store.conversations, hasLength(1));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(rig.peers.single.closeCount, greaterThan(0));
    expect(rig.harness.store.conversations, isEmpty);
    rig.peers.single.text('d' * 32, 'late callback');
    await tester.pump();
    expect(rig.harness.store.conversations, isEmpty);
    expect(find.byType(ChatRoomScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late additional invitation keeps the existing chat connected', (
    tester,
  ) async {
    final rig = await open(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    final existing = await rig.harness.registry.createWebInvitation();
    final active = rig.peers.single..connect();
    active.text('e' * 32, 'existing history');
    final offer = Completer<String>();
    late _DelayedPeer pending;
    rig.harness.registry.debugWebSessionFactory =
        ({onState, onTextFrame, onControl, onTransfer, onError}) =>
            pending = _DelayedPeer(
              offer,
              onState: onState,
              onTextFrame: onTextFrame,
              onControl: onControl,
              onTransfer: onTransfer,
              onError: onError,
            );
    final context = tester.element(find.byType(Scaffold));
    unawaited(
      showWebConnectionDialog(context, conversationId: existing.conversationId),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Create invitation code'),
    );
    await tester.pump();
    // Back/barrier/lock can dismiss a dialog while ICE gathering is pending.
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    offer.complete('IGW1.late-invitation');
    await tester.pumpAndSettle();
    expect(pending.closeCount, 1);
    expect(active.closeCount, 0);
    expect(
      rig.harness.store.conversation(existing.conversationId)!.online,
      isTrue,
    );
    expect(rig.harness.store.messageById('e' * 32)!.text, 'existing history');
    expect(tester.takeException(), isNull);
  });
}

class _DelayedPeer extends SecureWebUiPeer {
  _DelayedPeer(
    this.offer, {
    super.onState,
    super.onTextFrame,
    super.onControl,
    super.onTransfer,
    super.onError,
  });
  final Completer<String> offer;

  @override
  Future<String> createOffer() async {
    state = 'waiting';
    onState?.call(state);
    return offer.future;
  }
}
