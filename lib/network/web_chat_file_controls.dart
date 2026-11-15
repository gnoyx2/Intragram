part of 'web_chat_bridge.dart';

extension _WebChatFileControls on _WebRoom {
  void routeFileControl(
    _WebChatPeer? sender,
    Map<String, dynamic> control,
    String origin,
  ) {
    if (!['read', 'receipt', 'react', 'burn'].contains(control['k'])) return;
    final messageId = control['id'] as String;
    final route = forwarded.entries.firstWhereOrNull(
      (entry) => entry.key == messageId || entry.value.containsValue(messageId),
    );
    if (route == null) return;
    final sourceId = route.key;
    if (sourceId != messageId) {
      final owner = fileOwners[sourceId];
      if (owner != null && owner != sender) {
        sendTo(owner, {
          'k': 'room-control',
          'origin': origin,
          'control': {...control, 'id': sourceId},
        });
      }
      if (control['k'] == 'react' && store.messageById(sourceId) != null) {
        store.applyReaction(
          sourceId,
          origin,
          control['emoji'] as String,
          on: control['on'] as bool,
        );
      }
    }
    for (final target in route.value.entries) {
      if (target.key == sender || target.value == messageId) continue;
      sendTo(target.key, {
        'k': 'room-control',
        'origin': origin,
        'control': {...control, 'id': target.value},
      });
      if (control['k'] == 'burn') store.burnMessage(target.value);
    }
    if (control['k'] == 'burn') forwarded.remove(sourceId);
  }
}

FileTransfer _fileWithVoice(FileTransfer t) => FileTransfer(
  id: t.id,
  conversationId: t.conversationId,
  direction: t.direction,
  fileName: t.fileName,
  totalBytes: t.totalBytes,
  transferredBytes: t.transferredBytes,
  state: t.state,
  voice: true,
  encrypted: true,
  voiceBytes: t.voiceBytes,
  localPath: t.localPath,
  senderPeerId: t.senderPeerId,
);
