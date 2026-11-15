import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/message_bubble.dart';
import 'package:intragram/features/search/search_screen.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

// 스크린 리더가 읽는 말풍선 이름에는 상한이 있음: 긴 글은 안내와 앞부분만 읽고 전체는 복사로 봄
// (상한이 없으면 1 MiB 글이 이름 하나로 통째 나감). 화면에 보이는 글은 그대로
void main() {
  const notice = 'Long message.';
  const family = '👨‍👩‍👧‍👦';

  Future<Harness> pump(
    WidgetTester tester,
    String text, {
    String? replyTo,
  }) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1'));
    if (replyTo != null) {
      h.store.addMessage(
        msg(id: 'm0', dir: MessageDirection.incoming, text: replyTo),
      );
    }
    await tester.pumpWidget(
      h.wrap(
        Scaffold(
          body: SingleChildScrollView(
            child: MessageBubble(
              message: msg(
                id: 'm1',
                dir: MessageDirection.incoming,
                text: text,
                replyToId: replyTo == null ? null : 'm0',
              ),
            ),
          ),
        ),
      ),
    );
    return h;
  }

  String label(WidgetTester tester, Pattern shown) =>
      tester.getSemantics(find.textContaining(shown)).label;

  testWidgets('a message at the limit is read in full', (tester) async {
    final handle = tester.ensureSemantics();
    final text = 'HEAD ${'ab cd ' * 665}TAIL!';
    expect(text.length, 4000);

    await pump(tester, text);

    final spoken = label(tester, 'HEAD');
    expect(spoken, contains(text));
    expect(spoken, isNot(contains(notice)));
    handle.dispose();
  });

  testWidgets('a longer message is named by a notice and its first part', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final text = 'HEAD ${'ab cd ' * 8000}TAIL';

    await pump(tester, text);

    final spoken = label(tester, 'HEAD');
    expect(spoken, contains(notice));
    expect(spoken, contains('HEAD ab cd'));
    expect(spoken, isNot(contains('TAIL')));
    expect(spoken.length, lessThan(4300));
    expect(spoken.indexOf(notice), lessThan(spoken.indexOf('HEAD')));
    // 화면 글은 안 줄임
    expect(find.textContaining('TAIL'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the cut never splits an emoji', (tester) async {
    final handle = tester.ensureSemantics();

    await pump(tester, family * 4100);

    final spoken = label(tester, family);
    expect(family.allMatches(spoken).length, 4000);
    final rest = spoken.replaceAll(family, '');
    expect(rest.runes.where((r) => r > 0x2000), isEmpty);
    handle.dispose();
  });

  testWidgets('emoji count as one character each', (tester) async {
    final handle = tester.ensureSemantics();
    final text = family * 1000;
    expect(text.length, greaterThan(4000));

    await pump(tester, text);

    final spoken = label(tester, family);
    expect(family.allMatches(spoken).length, 1000);
    expect(spoken, isNot(contains(notice)));
    handle.dispose();
  });

  testWidgets('a reply carries only a snippet of a long original', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await pump(tester, 'short reply', replyTo: 'HEAD ${'ab cd ' * 8000}TAIL');

    final spoken = label(tester, 'short reply');
    expect(spoken, contains('HEAD ab cd'));
    expect(spoken, contains('short reply'));
    expect(spoken, isNot(contains('TAIL')));
    expect(spoken.length, lessThan(1300));
    handle.dispose();
  });

  testWidgets('a search hit carries only a snippet of a long message', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final h = Harness();
    addTearDown(h.dispose);
    h.store
      ..upsertConversation(conv('c1'))
      ..addMessage(
        msg(
          id: 'm1',
          dir: MessageDirection.incoming,
          text: 'HEAD ${'ab cd ' * 8000}TAIL',
        ),
      );

    await tester.pumpWidget(h.wrap(const SearchScreen()));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'TAIL');
    await tester.pump();

    final spoken = label(tester, 'HEAD ab cd');
    expect(spoken, isNot(contains('TAIL')));
    expect(spoken.length, lessThan(1300));
    handle.dispose();
  });
}
