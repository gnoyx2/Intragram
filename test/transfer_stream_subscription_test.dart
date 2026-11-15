import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';
import 'support/handshake_pair.dart' show conv;

void main() {
  test(
    'initial transfer snapshot cannot drop an immediate completion',
    () async {
      final store = InMemoryStore();
      store.upsertTransfer(
        const FileTransfer(
          id: 'file',
          conversationId: 'room',
          direction: TransferDirection.incoming,
          fileName: 'voice.wav',
          totalBytes: 44,
          state: TransferState.transferring,
        ),
      );
      final seen = <TransferState>[], complete = Completer<void>();
      final subscription = store.watchTransfers().listen((snapshot) {
        seen.add(snapshot.single.state);
        if (seen.length == 1) {
          store.updateTransfer(
            'file',
            (file) => file.copyWith(state: TransferState.complete),
          );
        } else if (snapshot.single.state == TransferState.complete &&
            !complete.isCompleted) {
          complete.complete();
        }
      });
      try {
        await complete.future.timeout(const Duration(seconds: 1));
        expect(seen, [TransferState.transferring, TransferState.complete]);
      } finally {
        await subscription.cancel();
        store.dispose();
      }
    },
  );

  test(
    'initial conversation snapshot cannot drop an immediate rename',
    () async {
      final store = InMemoryStore()
        ..upsertConversation(conv('room', 'initial'));
      final seen = <String>[], complete = Completer<void>();
      final subscription = store.watchConversations().listen((snapshot) {
        seen.add(snapshot.single.peerAlias);
        if (seen.length == 1) {
          store.updateConversation(
            'room',
            (room) => room.copyWith(peerAlias: 'changed'),
          );
        } else if (snapshot.single.peerAlias == 'changed' &&
            !complete.isCompleted) {
          complete.complete();
        }
      });
      try {
        await complete.future.timeout(const Duration(seconds: 1));
        expect(seen, ['initial', 'changed']);
      } finally {
        await subscription.cancel();
        store.dispose();
      }
    },
  );

  test('initial room snapshot cannot drop an immediate message', () async {
    final store = InMemoryStore()..upsertConversation(conv('room', 'initial'));
    void add(String id) => store.addMessage(
      EphemeralMessage(
        id: id,
        conversationId: 'room',
        direction: MessageDirection.incoming,
        kind: MessageKind.text,
        senderAlias: 'peer',
        createdAt: DateTime.now(),
        text: id,
        delivery: DeliveryState.delivered,
      ),
    );
    add('first');
    final seen = <List<String>>[], complete = Completer<void>();
    final subscription = store.watchRoom('room').listen((snapshot) {
      seen.add(snapshot.map((message) => message.id).toList());
      if (seen.length == 1) {
        add('second');
      } else if (snapshot.length == 2 && !complete.isCompleted) {
        complete.complete();
      }
    });
    try {
      await complete.future.timeout(const Duration(seconds: 1));
      expect(seen, [
        ['first'],
        ['first', 'second'],
      ]);
    } finally {
      await subscription.cancel();
      store.dispose();
    }
  });
}
