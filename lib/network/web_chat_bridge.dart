import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:collection/collection.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/constants.dart'
    show
        kFrameCeilingBytes,
        kMaxFrameBytes,
        kMaxInlineMessageBytes,
        kMaxVoiceNoteBytes,
        kSpillThresholdBytes;
import 'package:intragram/audit/evidence_entry.dart';
import 'package:intragram/core/mobile_file_source.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';
import 'web_chat_storage.dart';
import 'web_stream_io.dart';
import 'protocol.dart';
import 'web_peer.dart';
import 'web_peer_protocol.dart';
import 'web_peer_evidence.dart';

part 'web_chat_room.dart';
part 'web_chat_messages.dart';
part 'web_chat_files.dart';
part 'web_chat_batch.dart';
part 'web_chat_sources.dart';
part 'web_chat_budget.dart';
part 'web_chat_file_controls.dart';
part 'web_chat_transfer.dart';
part 'web_chat_control.dart';
part 'web_chat_integrity.dart';
part 'web_chat_invite.dart';

// Live web peers share the same store and native chat widgets as v7 peers.
class WebChatBridge {
  WebChatBridge({
    required this.store,
    required this.identity,
    this.chooseDirectory,
    this.blockedPeers = const {},
  }) {
    store.orgCredentials.addListener(_organizationChanged);
  }
  final InMemoryStore store;
  final AppIdentity identity;
  final Set<String> blockedPeers;
  final Future<String?> Function(String)? chooseDirectory;
  final rooms = <String, _WebRoom>{};
  final _files = <String, _WebRoom>{};
  final _heldBytes = <String, int>{};
  final _accepting = <String>{};
  final _sources = <_WebFileSource>{};
  bool _disposed = false;
  bool _mirroringOrganization = false;
  WebPeerSession Function({
    void Function(String)? onState,
    void Function(Map<String, dynamic>)? onTextFrame,
    void Function(Map<String, dynamic>)? onControl,
    void Function(WebPeerTransfer)? onTransfer,
    void Function(Object)? onError,
  })?
  sessionFactory;

  bool contains(String id) => rooms.containsKey(id);
  bool hasTransfer(String id) => _files.containsKey(id);
  Iterable<String> get activeIds => rooms.keys;

  _WebRoom _room(String? existing, bool hosting) {
    if (_disposed) throw StateError('disposed');
    if (existing != null && rooms.containsKey(existing)) {
      return rooms[existing]!;
    }
    if (existing != null && store.conversation(existing) != null) {
      throw const WebPeerProblem('session-in-use');
    }
    final id = existing ?? 'web-${webPeerNewId()}';
    final room = _WebRoom(this, id, hosting);
    rooms[id] = room;
    store.upsertConversation(
      Conversation(
        id: id,
        peerAlias: 'Web',
        peerPlatform: 'Browser',
        transport: PeerTransport.app,
        startedAt: DateTime.now(),
        online: false,
      ),
    );
    return room;
  }

  Future<({String conversationId, String code})> createInvitation({
    String? conversationId,
  }) async {
    final room = _room(conversationId, true);
    final peer = _newInvitee(room);
    try {
      return (conversationId: room.id, code: await peer.session.createOffer());
    } on Object {
      room.peers.remove(peer.id);
      await peer.session.close();
      if (room.peers.isEmpty && conversationId == null) {
        rooms.remove(room.id);
        store.wipeConversation(room.id);
      }
      rethrow;
    }
  }

  // expectedPeerId: 앱 링크가 나른 자동 초대면 그 앱의 신원. 다른 신원이 호스트로 나오면 끊음
  Future<({String conversationId, String code})> joinInvitation(
    String code, {
    String? expectedPeerId,
    void Function(String conversationId)? onRoomCreated,
  }) async {
    final room = _room(null, false);
    onRoomCreated?.call(room.id);
    // The peer is created after code validation by its session implementation.
    final target = room.addPeer(false)..expectedPeerId = expectedPeerId;
    try {
      return (
        conversationId: room.id,
        code: await target.session.acceptOffer(code),
      );
    } on Object {
      await closeRoom(room.id);
      store.wipeConversation(room.id);
      rethrow;
    }
  }

  Future<void> closeRoom(String id) async {
    final room = rooms[id];
    if (room == null) return;
    room.closing = true;
    room.epoch++;
    final closing = <Future<void>>[];
    for (final peer in room.peers.values.toList()) {
      closing.add(peer.session.close());
      peer.settle(false);
      room.forgetOrganization(peer);
      peer.proof.clear();
      peer.clearPendingIdentity();
    }
    for (final transferId in room.fileOwners.keys) {
      final transfer = store.transfer(transferId);
      if (transfer == null ||
          ![
            TransferState.offered,
            TransferState.accepted,
            TransferState.transferring,
          ].contains(transfer.state)) {
        continue;
      }
      _heldBytes.remove(transferId);
      store.updateTransfer(
        transferId,
        (t) => t.copyWith(state: TransferState.failed),
      );
    }
    for (final source in _sources.where((s) => s.room == room).toList()) {
      _releaseSource(source);
    }
    room.streamOffers.clear();
    room.relayBatches.clear();
    store.roomIntegrity.remove(id);
    store.setConversationOnline(id, online: false);
    store.clearVerified(id);
    await Future.wait(closing);
  }

  Future<void> dispose() async {
    _disposed = true;
    store.orgCredentials.removeListener(_organizationChanged);
    final closing = [for (final id in rooms.keys.toList()) closeRoom(id)];
    rooms.clear();
    _files.clear();
    _heldBytes.clear();
    _accepting.clear();
    clearWebReceived();
    await Future.wait(closing);
  }

  void _organizationChanged() {
    if (_mirroringOrganization) return;
    for (final room in rooms.values) {
      for (final peer in room.connected) {
        unawaited(peer.syncOrganization());
      }
    }
  }
}

class _WebRoom {
  _WebRoom(this.bridge, this.id, this.hosting);
  final WebChatBridge bridge;
  final String id;
  final bool hosting;
  final peers = <String, _WebChatPeer>{};
  final origins = <String, String>{};
  final fileOwners = <String, _WebChatPeer>{};
  final fileBytes = <String, Uint8List>{};
  final streamOffers = <String>{};
  final relayingFiles = <String>{};
  final relayBatches = <String, String>{};
  final forwarded = <String, Map<_WebChatPeer, String>>{};
  final signedMessages = <String>{};
  final outgoing = <String, _WebFileSource>{};
  final destinations = <String, String>{};
  final metas = <String, Map<String, dynamic>>{};
  String selfId = webPeerNewId();
  String? hostId;
  Map<String, String> members = {};
  Map<String, String> authorIds = {};
  bool closing = false;
  int epoch = 0;
  InMemoryStore get store => bridge.store;
  AppIdentity get identity => bridge.identity;
  // 방 멤버: 연결됐고, 자동 초대 링크면 기대한 신원까지 증명한 상대
  Iterable<_WebChatPeer> get connected =>
      peers.values.where((p) => p.session.state == 'connected' && p.bound);
  String get remoteAlias => connected.firstOrNull?.alias ?? 'Web';
}
