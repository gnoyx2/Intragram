import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/chat/widgets/add_people_sheet.dart';
import 'package:intragram/features/portal/web_connection_dialog.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/web_peer.dart';

import '../support/secure_web_ui_peer.dart';
import '_harness.dart';

class _Peer extends SecureWebUiPeer {
  _Peer({super.onState, super.onTextFrame, super.onControl, super.onTransfer});
  @override
  Future<String> acceptOffer(String code) async => 'IGW1.test-answer';
}

// 자동 초대 호출만 기록함 (실제 v7 링크 교환은 web_auto_invite_test가 봄)
class _Registry extends LinkRegistry {
  _Registry({required super.store, required super.identity})
    : super(crypto: CryptoEngine());
  final moved = <(String, String)>[];
  @override
  Future<int> inviteConversationToWebRoom(String from, String roomId) async {
    moved.add((from, roomId));
    return 1;
  }
}

void main() {
  late AppIdentity identity;
  setUpAll(() async => identity = await AppIdentity.create());

  ({Harness harness, List<_Peer> peers}) rig(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final h = Harness(
      registryBuilder: (store, _) =>
          _Registry(store: store, identity: identity),
    );
    addTearDown(h.dispose);
    final peers = <_Peer>[];
    h.registry.debugWebSessionFactory =
        ({onState, onTextFrame, onControl, onTransfer, onError}) {
          final peer = _Peer(
            onState: onState,
            onTextFrame: onTextFrame,
            onControl: onControl,
            onTransfer: onTransfer,
          );
          peers.add(peer);
          return peer;
        };
    return (harness: h, peers: peers);
  }

  Future<void> openChat(WidgetTester tester, Harness h, String id) async {
    await tester.pumpWidget(h.wrap(ChatRoomScreen(conversationId: id)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
  }

  testWidgets('a v7 chat brings a browser into a new encrypted room and then '
      'invites its app peers there', (tester) async {
    final r = rig(tester);
    r.harness.store.upsertConversation(conv('c1', secure: true));
    await tester.pumpWidget(
      r.harness.wrap(
        Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () => showAddPeopleSheet(context, ref, 'c1'),
              child: const Text('add'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();
    expect(find.textContaining('new encrypted room'), findsOneWidget);
    await tester.tap(find.text('Encrypted app–web connection'));
    await tester.pumpAndSettle();

    // 옮기는 흐름은 내가 호스트라 '코드로 참여' 선택지가 없음
    expect(find.byType(WebConnectionDialog), findsOneWidget);
    expect(find.text('Join with a code'), findsNothing);
    expect(find.textContaining('new encrypted room'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Create invitation code'),
    );
    await tester.pumpAndSettle();
    final registry = r.harness.registry as _Registry;
    expect(registry.moved, isEmpty);
    await tester.enterText(
      find.byKey(const Key('shared-web-remote-code')),
      'IGW1.response',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();

    // 브라우저의 응답 코드를 받아 연결을 시작한 뒤에만 앱 상대를 새 방으로 부름
    final room = registry.moved.single.$2;
    expect(registry.moved.single.$1, 'c1');
    expect(registry.hostsWebRoom(room), isTrue);
    expect(find.byType(ChatRoomScreen), findsOneWidget);
    expect(find.textContaining("couldn't be invited"), findsOneWidget);
  });

  testWidgets('only the host of a web room is offered Add people', (
    tester,
  ) async {
    final r = rig(tester);
    final hosted = await r.harness.registry.createWebInvitation();
    r.peers.single.connect();
    await openChat(tester, r.harness, hosted.conversationId);
    expect(find.text('Add people'), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    final joined = await r.harness.registry.joinWebInvitation('IGW1.invite');
    r.peers.last.connect();
    await openChat(tester, r.harness, joined.conversationId);
    expect(find.text('End conversation'), findsOneWidget);
    expect(find.text('Add people'), findsNothing);
  });

  test('automatic invite failures map to their own guidance', () {
    expect(
      autoInviteError(const WebPeerProblem('auto-invite-refused')),
      'secureWeb.autoInviteRefused',
    );
    expect(
      autoInviteError(const WebPeerProblem('room-full')),
      'secureWeb.error.room-full',
    );
    expect(autoInviteError(StateError('x')), 'secureWeb.autoInviteFailed');
  });
}
