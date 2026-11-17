import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/home/web_leave_guard.dart';

import '_harness.dart';

// 브라우저 뒤로: 대화 창에 대화가 떠 있으면 그 대화만 닫고, 홈에서만 페이지를 떠날지 물음.
// 대화 창의 NavigatorPopHandler와 이 가드가 같은 홈 경로라 뒤로 한 번을 둘 다 받음
void main() {
  testWidgets('back with a chat open closes only the chat', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1'));
    await tester.pumpWidget(h.wrap(const _Home()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('chat'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('chat'), findsNothing);
    expect(find.text('Leave this page?'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Leave this page?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.text('Leave this page?'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}

// 홈 구조만 줄여 옮김: 가드 안에 대화 창 Navigator와 그 NavigatorPopHandler
class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  final _pane = GlobalKey<NavigatorState>();
  bool _chat = false;

  @override
  Widget build(BuildContext context) => WebLeaveGuard(
    web: true,
    chatOpen: _chat,
    child: NavigatorPopHandler<Object?>(
      onPopWithResult: (_) => _pane.currentState?.maybePop(),
      child: Navigator(
        key: _pane,
        pages: [
          MaterialPage<void>(
            key: const ValueKey('list'),
            child: Scaffold(
              body: TextButton(
                onPressed: () => setState(() => _chat = true),
                child: const Text('open'),
              ),
            ),
          ),
          if (_chat)
            const MaterialPage<void>(
              key: ValueKey('chat'),
              child: Scaffold(body: Text('chat')),
            ),
        ],
        onDidRemovePage: (page) {
          if (page.key == const ValueKey('chat')) {
            setState(() => _chat = false);
          }
        },
      ),
    ),
  );
}
