import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/discovery_engine.dart';

// isRunning은 provider state 밖이라 스캔이 죽거나 살아날 때 홈이 다시 읽도록 알려야 함
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a scan error stops the native browse and tells the home screen, '
      'and the next refresh clears it again', () {
    fakeAsync((async) {
      final platform = _FakeBonsoirPlatform();
      final originalPlatform = BonsoirPlatformInterface.instance;
      BonsoirPlatformInterface.instance = platform;
      addTearDown(() => BonsoirPlatformInterface.instance = originalPlatform);
      final originalBroadcast = DiscoveryController.createBroadcast;
      DiscoveryController.createBroadcast = (_) => _NoopBroadcast();
      addTearDown(
        () => DiscoveryController.createBroadcast = originalBroadcast,
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);
      var notified = 0;
      container.listen(
        discoveryControllerProvider,
        (previous, next) => notified++,
      );
      final notifier = container.read(discoveryControllerProvider.notifier);

      unawaited(
        notifier.start(
          identity: AppIdentity(
            peerId: 'me',
            alias: 'swift-heron-3',
            platform: 'Android',
          ),
          port: 7890,
        ),
      );
      async.elapse(const Duration(seconds: 1));
      expect(notifier.isRunning, isTrue);
      final first = platform.discoveries.single;

      // bonsoir가 넘긴 네이티브 오류: 홈에 알리고, 아직 돌 수 있는 네이티브 탐색은 멈춤
      var before = notified;
      first.fail();
      async.flushMicrotasks();
      expect(notifier.isRunning, isFalse);
      expect(first.stopped, isTrue);
      expect(notified, greaterThan(before));

      // 이전 버그: 새로고침으로 스캔이 살아나도 알림이 없어 '검색이 멈췄어요'가 계속 남았음
      before = notified;
      unawaited(notifier.refresh());
      async.elapse(const Duration(seconds: 1));
      expect(platform.discoveries, hasLength(2));
      expect(notifier.isRunning, isTrue);
      expect(notified, greaterThan(before));

      unawaited(notifier.stop());
      async.elapse(const Duration(milliseconds: 200));
    });
  });
}

class _NoopBroadcast implements BroadcastSession {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

class _FakeBonsoirPlatform extends BonsoirPlatformInterface {
  final discoveries = <_FakeDiscoveryAction>[];

  @override
  BonsoirAction<BonsoirBroadcastEvent> createBroadcastAction(
    BonsoirService service, {
    bool printLogs = false,
  }) => throw UnimplementedError('the test swaps createBroadcast');

  @override
  BonsoirAction<BonsoirDiscoveryEvent> createDiscoveryAction(
    String type, {
    bool printLogs = false,
  }) {
    final action = _FakeDiscoveryAction();
    discoveries.add(action);
    return action;
  }
}

class _FakeDiscoveryAction implements BonsoirAction<BonsoirDiscoveryEvent> {
  final _events = StreamController<BonsoirDiscoveryEvent>.broadcast(sync: true);
  bool _initialized = false;
  bool stopped = false;

  @override
  Stream<BonsoirDiscoveryEvent>? get eventStream => _events.stream;

  @override
  Future<void> initialize() async => _initialized = true;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {
    stopped = true;
    await _events.close();
  }

  @override
  bool get isReady => _initialized && !stopped;

  @override
  bool get isStopped => stopped;

  // bonsoir가 네이티브 onError를 eventStream 오류로 넘기는 모양 그대로
  void fail() => _events.addError(
    PlatformException(code: 'discoveryError', message: 'error 7'),
  );
}
