import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/web_chat_bridge.dart';
import 'package:intragram/network/room_integrity.dart';
import 'package:intragram/network/org_auth.dart';
import 'package:intragram/network/web_peer_protocol.dart';
import 'support/web_chat_rig.dart';
import 'web_peer_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WebChatRig host, first, second;
  setUp(() async {
    host = await WebChatRig.create('AA');
    first = await WebChatRig.create('BB');
    second = await WebChatRig.create('CC');
  });
  tearDown(() async {
    await host.dispose();
    await first.dispose();
    await second.dispose();
  });

  test(
    'signed group authors, checkpoints, replay and downgrade use the shared book',
    () async {
      await host.connect(first);
      await host.connect(second);
      await webPeerUntil(() => first.store.conversation(first.room!)!.isRoom);
      await host.bridge.sendText(host.room!, 'Host signed message');
      await first.bridge.sendText(first.room!, 'Member signed message');
      await webPeerUntil(
        () =>
            host.store.messages(host.room!).length == 2 &&
            first.store.messages(first.room!).length == 2 &&
            second.store.messages(second.room!).length == 2,
      );
      for (final party in [host, first, second]) {
        expect(
          party.store.roomIntegrity.status(party.room!),
          RoomIntegrityStatus.verified,
        );
        expect(party.errors, isEmpty);
      }
      final signed = first.connections.single.channel.sent
          .where((data) => !data.isBinary)
          .map((data) => jsonDecode(data.text) as Map)
          .where((frame) => frame['kind'] == 'control')
          .map((frame) => (frame['control'] as Map).cast<String, dynamic>())
          .lastWhere(
            (control) =>
                control['k'] == 'native-room' && control['frame']['k'] == 'msg',
          );
      final envelope = (signed['frame'] as Map).cast<String, dynamic>();
      expect(envelope['authorPeerId'], first.identity.peerId);
      await first.sessions.single.sendControl({
        'k': 'meta',
        'id': envelope['id'],
        'ttl': 5,
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(host.store.messageById(envelope['id'])!.ttlSeconds, 0);
      await first.sessions.single.sendControl(signed);
      await first.sessions.single.sendText('stripped signature', id: 'd' * 32);
      await webPeerUntil(
        () =>
            host.store.roomIntegrity.status(host.room!) ==
            RoomIntegrityStatus.conflict,
      );
      expect(host.store.messageById('d' * 32), isNull);
      expect(host.store.messages(host.room!), hasLength(2));
      expect(host.sessions.first.state, 'connected');
      await first.sessions.single.sendControl({
        ...signed,
        'frame': {...envelope, 'id': 'e' * 32, 'text': 'forged'},
      });
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(host.store.messageById('e' * 32), isNull);
      expect(second.store.messageById('e' * 32), isNull);
    },
  );

  test(
    'promotion and roster updates preserve only the corresponding SAS checks',
    () async {
      await host.connect(first);
      final hostSas = host.sessions.single.verificationCode;
      host.bridge.verify(host.room!, sas: hostSas);
      first.bridge.verify(
        first.room!,
        sas: first.sessions.single.verificationCode,
      );
      await webPeerUntil(() => host.store.conversation(host.room!)!.verified);
      await host.connect(second);
      await webPeerUntil(() => first.store.conversation(first.room!)!.isRoom);
      final member = host.store.conversation(host.room!)!.members.values;
      expect(member.where((m) => m.verified), hasLength(1));
      expect(
        member.where((m) => !m.localVerified && !m.peerVerified),
        hasLength(1),
      );
      expect(host.store.conversation(host.room!)!.verified, isFalse);
      final hostMember = first.store
          .conversation(first.room!)!
          .members
          .values
          .singleWhere((m) => m.sas != null);
      expect(hostMember.verified, isTrue);
      first.bridge.sendControl(first.room!, {
        'k': 'rename',
        'alias': 'Renamed',
      });
      await webPeerUntil(
        () => host.store
            .conversation(host.room!)!
            .members
            .values
            .any((m) => m.alias == 'Renamed'),
      );
      expect(
        host.store
            .conversation(host.room!)!
            .members
            .values
            .where((m) => m.verified),
        hasLength(1),
      );
      expect(
        first.store
            .conversation(first.room!)!
            .members
            .values
            .singleWhere((m) => m.sas != null)
            .verified,
        isTrue,
      );
    },
  );

  test(
    'native controls validate the signed envelope and exact byte cap',
    () async {
      await host.connect(first);
      await host.connect(second);
      await host.bridge.sendText(host.room!, 'signed');
      final control = host.connections.last.channel.sent
          .where((data) => !data.isBinary)
          .map((data) => jsonDecode(data.text) as Map)
          .where((frame) => frame['kind'] == 'control')
          .map((frame) => (frame['control'] as Map).cast<String, dynamic>())
          .lastWhere(
            (control) =>
                control['k'] == 'native-room' && control['frame']['k'] == 'msg',
          );
      expect(() => webPeerValidateControl(control), returnsNormally);
      final frame = (control['frame'] as Map).cast<String, dynamic>();
      for (final changed in [
        {...frame, 'authorCounter': 1.5},
        {...frame, 'authorSig': 'bad'},
        {...frame, 'padding': 'x' * 8192},
      ]) {
        expect(
          () => webPeerValidateControl({...control, 'frame': changed}),
          throwsA(isA<WebPeerProblem>()),
        );
      }
    },
  );
  test('closing during author signing prevents a late unsigned send', () async {
    await host.connect(first);
    await host.connect(second);
    final pending = host.bridge.sendText(host.room!, 'close while signing');
    await host.bridge.closeRoom(host.room!);
    await pending;
    expect(first.store.messages(first.room!), isEmpty);
    expect(second.store.messages(second.room!), isEmpty);
    expect(host.store.roomIntegrity.scope(host.room!), isNull);
  });
  test(
    'organization changes propagate once and clear on withdrawal or close',
    () async {
      await host.connect(first);
      final memberId = host.store.conversation(host.room!)!.members.keys.single;
      final credential = await issueDemoCredential(
        first.identity,
        org: 'Demo',
        dept: 'QA',
        role: 'Test',
      );
      first.store.orgCredentials.activate(credential);
      await webPeerUntil(
        () => host.store.orgCredentials.statusOf(memberId)?.verified == true,
      );
      final count = first.connections.single.channel.sent.length;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(first.connections.single.channel.sent.length, count);
      first.store.orgCredentials.deactivate();
      await webPeerUntil(
        () => host.store.orgCredentials.statusOf(memberId) == null,
      );
      first.store.orgCredentials.activate(credential);
      await webPeerUntil(
        () => host.store.orgCredentials.statusOf(memberId)?.verified == true,
      );
      await host.bridge.closeRoom(host.room!);
      expect(host.store.orgCredentials.statusOf(memberId), isNull);
    },
  );
}
