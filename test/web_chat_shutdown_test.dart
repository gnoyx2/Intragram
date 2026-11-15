import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:stream_channel/stream_channel.dart';

import 'support/secure_web_ui_peer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final failClose in [false, true]) {
    test(
      'native links close while WebRTC teardown ${failClose ? 'fails' : 'waits'}',
      () async {
        final store = InMemoryStore();
        final registry = LinkRegistry(
          store: store,
          crypto: CryptoEngine(),
          identity: await AppIdentity.create(),
        );
        final wire = StreamChannelController<dynamic>();
        wire.local.stream.listen((_) {});
        final pending = Completer<void>();
        addTearDown(() async {
          if (!pending.isCompleted) pending.complete();
          await registry.disposeAll();
          store.dispose();
        });
        await registry.acceptInbound(
          wire.foreign,
          remoteHost: '192.168.1.9',
          remotePort: 7890,
        );
        final native = registry.linkFor(store.conversations.single.id)!;
        registry.debugWebSessionFactory =
            ({onState, onTextFrame, onControl, onTransfer, onError}) =>
                _ClosingPeer(
                  pending.future,
                  onState: onState,
                  onTextFrame: onTextFrame,
                  onControl: onControl,
                  onTransfer: onTransfer,
                  onError: onError,
                );
        await registry.createWebInvitation();
        final closing = registry.disposeAll();
        final completed = expectLater(
          closing,
          failClose ? throwsStateError : completes,
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final nativeClosedBeforeWeb = native.isClosed;
        if (failClose) {
          pending.completeError(StateError('WebRTC teardown failed'));
        } else {
          pending.complete();
        }
        await completed;
        expect(
          nativeClosedBeforeWeb,
          isTrue,
          reason: 'WebRTC plugin teardown must not keep native traffic alive',
        );
        expect(native.isClosed, isTrue);
      },
    );
  }
}

class _ClosingPeer extends SecureWebUiPeer {
  _ClosingPeer(
    this.closed, {
    super.onState,
    super.onTextFrame,
    super.onControl,
    super.onTransfer,
    super.onError,
  });
  final Future<void> closed;

  @override
  Future<void> close() async {
    await super.close();
    await closed;
  }
}
