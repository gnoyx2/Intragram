import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_commands.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/home/home_screen.dart';
import 'package:intragram/features/home/widgets/conversation_tile.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

// 단축키를 받으려고 화면 전체를 감싼 autofocus 초점이 Tab 칸이 되면 보이지 않는 칸이 생기고
// 읽기 순서가 어긋나 본문 버튼을 건너뜀
Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = Harness();
  addTearDown(h.dispose);
  h.store
    ..upsertConversation(conv('c1'))
    ..addMessage(msg(id: 'm1', dir: MessageDirection.incoming, text: 'hi'));
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    h.wrap(
      const HomeScreen(),
      navigatorKey: key,
      builder: (context, child) => AppCommands(
        navigatorKey: key,
        unlocked: true,
        onNewConnection: (_) {},
        child: child!,
      ),
    ),
  );
  await tester.pump();
}

// scope 안에서 단축키용으로 autofocus를 건 첫 Focus의 노드
FocusNode _shortcutFocusIn(WidgetTester tester, Finder scope) {
  final focus = find
      .descendant(
        of: scope,
        matching: find.byWidgetPredicate((w) => w is Focus && w.autofocus),
      )
      .first;
  final child = tester.widget<Focus>(focus).child;
  return Focus.of(tester.element(find.byWidget(child)));
}

Future<List<FocusNode?>> _tabStops(WidgetTester tester, int count) async {
  final stops = <FocusNode?>[];
  for (var i = 0; i < count; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    stops.add(FocusManager.instance.primaryFocus);
  }
  return stops;
}

void main() {
  testWidgets('Tab never stops on the home shortcut focus', (tester) async {
    await _pumpHome(tester);
    final shortcut = _shortcutFocusIn(tester, find.byType(HomeScreen));
    // 빈 대화 칸 경로가 초점을 먼저 잡지 않아 목록의 단축키 초점에서 시작함 (Ctrl+Tab이 바로 먹음)
    expect(primaryFocus, shortcut);

    final stops = await _tabStops(tester, 24);
    expect(stops, isNot(contains(shortcut)));
    expect(stops.toSet().length, greaterThan(3));
  });

  // 넓은 창의 빈 대화 칸(경로 초점 범위, 창 전체 높이)이 Tab 후보로 남으면 읽기 순서가 x 좌표 순으로
  // 무너지고, 그 칸에 들어간 뒤로 Tab이 갇힘
  testWidgets('Tab reads the list top-down and never enters the empty pane', (
    tester,
  ) async {
    await _pumpHome(tester);

    final stops = await _tabStops(tester, 24);
    final rects = [for (final n in stops) n!.rect];
    expect(rects.where((r) => r.left > 360), isEmpty);
    final tile = tester.getRect(find.byType(ConversationTile));
    final firstTile = rects.indexWhere((r) => r.overlaps(tile));
    final firstHeader = rects.indexWhere((r) => r.top < 60);
    expect(firstHeader, isNonNegative);
    expect(firstTile, greaterThan(firstHeader));
  });

  // 빈 대화 칸은 초점을 못 받음: 대화를 닫으면 초점이 홈 안으로 돌아와 Tab·Ctrl+Tab이 그대로 먹어야 함
  testWidgets('closing the pane chat hands the keyboard back to the list', (
    tester,
  ) async {
    await _pumpHome(tester);
    await tester.tap(find.byType(ConversationTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ChatRoomScreen), findsNothing);
    expect(primaryFocus, _shortcutFocusIn(tester, find.byType(HomeScreen)));

    final stops = await _tabStops(tester, 12);
    expect(
      [for (final n in stops) n!.rect].where((r) => r.left > 360),
      isEmpty,
    );
    expect(stops.toSet().length, greaterThan(3));
  });

  testWidgets('Tab never stops on the chat shortcut focus', (tester) async {
    await _pumpHome(tester);
    await tester.tap(find.byType(ConversationTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final shortcut = _shortcutFocusIn(tester, find.byType(ChatRoomScreen));

    final stops = await _tabStops(tester, 24);
    expect(stops, isNot(contains(shortcut)));
    expect(stops.toSet().length, greaterThan(3));
  });
}
