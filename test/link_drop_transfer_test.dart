import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/store/models.dart';

import 'support/incoming_cleanup_rig.dart';
import 'support/transfer_rig.dart';

Future<void> _settle() => pumpEventQueue(times: 60);

// 1:1 링크가 갑자기 끊겨도(iOS가 백그라운드로 가며 소켓을 닫는 경우 등) 전송 칸이 '상대 기다리는 중'에
// 멈추지 않고 실패로 바뀌어, 다시 연결한 뒤 재시도로 이어 보낼 수 있어야 함. 대화를 끝내면 남긴 소스를 놓음
void main() {
  group('sender', () {
    test(
      'a dropped 1:1 link turns an offered file into a retryable failure',
      () async {
        final rig = await TransferRig.create();
        final t = await rig.offerVoice();
        expect(rig.store.transfer(t.id)!.state, TransferState.offered);

        await rig.remote.close();
        await _settle();

        expect(rig.store.transfer(t.id)!.state, TransferState.failed);
        expect(
          rig.registry.outgoingSource(t.id),
          isNotNull,
          reason: 'kept so Retry can resend after reconnecting',
        );
      },
    );

    test('ending the conversation releases the kept source', () async {
      final rig = await TransferRig.create();
      final t = await rig.offerVoice();
      await rig.remote.close();
      await _settle();

      await rig.registry.disconnect(t.conversationId);
      await _settle();

      expect(rig.registry.outgoingSource(t.id), isNull);
    });
  });

  group('receiver', () {
    final rig = IncomingCleanupRig();
    setUp(rig.setUp);
    tearDown(rig.tearDown);

    test('a dropped 1:1 link fails an open incoming file so Retry can ask '
        'the sender again', () async {
      rig.store.upsertTransfer(rig.offer('t'));

      await rig.incoming.handleLinkClosed('c');

      expect(rig.store.transfer('t')!.state, TransferState.failed);
    });
  });
}
