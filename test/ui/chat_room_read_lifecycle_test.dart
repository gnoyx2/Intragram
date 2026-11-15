import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

void main() {
  testWidgets('an open chat marks new messages read only while resumed', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1', secure: true, verified: true));
    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    // A background tab, another focused window or a backgrounded phone app.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    h.store.addMessage(
      msg(id: 'm1', dir: MessageDirection.incoming, text: 'unseen', ttl: 5),
    );
    await tester.pump();
    expect(h.store.messageById('m1')!.delivery, isNot(DeliveryState.read));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(h.store.messageById('m1')!.delivery, DeliveryState.read);
    // Read-triggered expiry starts only now; let it finish.
    await tester.pump(const Duration(seconds: 6));
    expect(h.store.messageById('m1'), isNull);
    await tester.pump(const Duration(milliseconds: 350)); // 고스트 페이드아웃 flush
  });
}
