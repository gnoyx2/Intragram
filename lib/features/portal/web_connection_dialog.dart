import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/features/chat/open_chat.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/web_peer.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';
import 'package:intragram/widgets/completed_dialog.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intragram/core/qr_image.dart';

part 'web_connection_fields.dart';

Future<void> showWebConnectionDialog(
  BuildContext context, {
  String? conversationId,
  String? invitation,
  String? moveFrom,
}) async {
  final id = await showCompletedDialog<String>(
    context: context,
    builder: (_) => WebConnectionDialog(
      conversationId: conversationId,
      invitation: invitation,
      moveFrom: moveFrom,
    ),
  );
  if (id != null && context.mounted) openChat(context, id);
}

class WebConnectionDialog extends ConsumerStatefulWidget {
  const WebConnectionDialog({
    this.conversationId,
    this.invitation,
    this.moveFrom,
    super.key,
  });
  final String? conversationId;
  final String? invitation;
  // 이 v7 대화의 앱 상대를 새 WebRTC 방으로 데려옴 (브라우저의 응답 코드를 받아 연결을 시작하면 바로 자동 초대)
  final String? moveFrom;
  @override
  ConsumerState<WebConnectionDialog> createState() => _WebConnectionState();
}

class _WebConnectionState extends ConsumerState<WebConnectionDialog> {
  final _remote = TextEditingController(), _local = TextEditingController();
  String? _id, _error;
  bool _join = false, _busy = false, _generated = false, _kept = false;
  late final LinkRegistry _registry;
  late final InMemoryStore _store;
  S get _s => S.of(context);

  @override
  void initState() {
    super.initState();
    _registry = ref.read(linkRegistryProvider);
    _store = ref.read(inMemoryStoreProvider);
    if (widget.invitation != null) {
      _join = true;
      _remote.text = widget.invitation!;
    }
  }

  void _update(VoidCallback change) => setState(change);

  Future<void> _readQr() => _run(() async {
    final value = await pickQrImage();
    if (value != null && mounted) setState(() => _remote.text = value);
  });

  Future<void> _showQr() => showCompletedDialog<void>(
    context: context,
    builder: (context) => AppAlertDialog(
      cupertino: false,
      title: Text(_s.t('secureWeb.myCode')),
      content: SizedBox(
        width: 300,
        height: 300,
        child: QrImageView(
          data: _local.text,
          backgroundColor: Colors.white,
          errorCorrectionLevel: QrErrorCorrectLevel.L,
        ),
      ),
      actions: dialogActions(context, [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_s.t('common.close')),
        ),
      ]),
    ),
  );

  Future<void> _run(Future<void> Function() action) async {
    // 입력창을 비활성으로 바꾸기 전에 포커스부터 내림: 폰에선 키보드가 내려가고, 스크린리더를 켠
    // 폰 브라우저에서 입력 중인 칸의 설정을 바꾸다 나는 Flutter 엔진 예외도 피함
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = _s.t(switch (error) {
            QrImageUnreadable() => 'qr.unreadable',
            WebPeerProblem(code: 'invalid-code') =>
              'secureWeb.error.invalid-code',
            WebPeerProblem(code: 'session-in-use') =>
              'secureWeb.error.session-in-use',
            WebPeerProblem(code: 'room-full') => 'secureWeb.error.room-full',
            WebPeerProblem(code: 'unexpected-answer') =>
              'secureWeb.error.unexpected-answer',
            WebPeerProblem(code: 'session-closed') =>
              'secureWeb.error.session-closed',
            WebPeerProblem(code: 'ice-timeout') =>
              'secureWeb.error.ice-timeout',
            WebPeerProblem(code: 'connection-failed') =>
              'secureWeb.error.connection-failed',
            WebPeerProblem(code: 'connection-timeout') =>
              'secureWeb.error.connection-timeout',
            WebPeerProblem(code: 'connection-closed') =>
              'secureWeb.error.connection-closed',
            WebPeerProblem(code: 'invalid-channel') =>
              'secureWeb.error.invalid-channel',
            _ => 'secureWeb.error.generic',
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() => _run(() async {
    final registry = _registry;
    final result = _join
        ? await registry.joinWebInvitation(_remote.text)
        : await registry.createWebInvitation(
            conversationId: widget.conversationId,
          );
    if (!mounted) {
      if (widget.conversationId == null) {
        await registry.disconnect(result.conversationId);
        _store.wipeConversation(result.conversationId);
      } else {
        await registry.cancelWebInvitation(result.conversationId);
      }
      return;
    }
    setState(() {
      _id = result.conversationId;
      _local.text = result.code;
      _remote.clear();
      _generated = true;
    });
  });

  Future<void> _open() => _run(() async {
    if (!_join) {
      await _registry.acceptWebAnswer(_id!, _remote.text);
    }
    if (!mounted) return;
    _kept = true;
    final moveFrom = widget.moveFrom;
    if (moveFrom != null && !_join) {
      final messenger = ScaffoldMessenger.of(context);
      final some = _s.t('secureWeb.autoInviteSome');
      unawaited(
        _registry.inviteConversationToWebRoom(moveFrom, _id!).then((failed) {
          if (failed > 0) messenger.showSnackBar(SnackBar(content: Text(some)));
        }),
      );
    }
    Navigator.pop(context, _id);
  });

  @override
  void dispose() {
    if (!_kept && _id != null && widget.conversationId == null) {
      _registry.disconnect(_id!).then((_) => _store.wipeConversation(_id!));
    } else if (!_kept && _id != null) {
      _registry.cancelWebInvitation(_id!);
    }
    _remote.dispose();
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppAlertDialog(
    cupertino: false,
    title: Text(_s.t('secureWeb.open')),
    content: SizedBox(width: 560, child: _fields()),
    actions: dialogActions(context, [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: Text(_s.t('common.cancel')),
      ),
      if (_generated)
        FilledButton(
          onPressed: _busy ? null : _open,
          child: Text(
            _join ? _s.t('secureWeb.openChat') : _s.t('secureWeb.connect'),
          ),
        )
      else
        FilledButton(
          onPressed: _busy ? null : _generate,
          child: Text(
            _s.t(_join ? 'secureWeb.makeAnswer' : 'secureWeb.makeInvite'),
          ),
        ),
    ]),
  );
}
