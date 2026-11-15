import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/discovery_engine.dart';
import 'package:intragram/network/web_peer.dart' show WebPeerProblem;
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/empty_state.dart';
import 'package:intragram/widgets/empty_state_art.dart';
import 'package:intragram/features/portal/web_connection_dialog.dart';

// 자동 초대 실패 이유별 안내 문구 키
String autoInviteError(Object error) => switch (error) {
  WebPeerProblem(code: 'auto-invite-refused') => 'secureWeb.autoInviteRefused',
  WebPeerProblem(code: 'room-full') => 'secureWeb.error.room-full',
  _ => 'secureWeb.autoInviteFailed',
};

Future<void> showAddPeopleSheet(
  BuildContext context,
  WidgetRef ref,
  String conversationId,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _AddPeopleSheet(conversationId: conversationId),
  );
}

class _AddPeopleSheet extends ConsumerStatefulWidget {
  const _AddPeopleSheet({required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<_AddPeopleSheet> createState() => _AddPeopleSheetState();
}

class _AddPeopleSheetState extends ConsumerState<_AddPeopleSheet> {
  final Set<String> _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    // 이미 이 방에 있는 피어는 뺌: discovery는 멤버십을 몰라서 목록에 남는데, 다시 고르면
    // 연결 중복 거르기가 방 멤버는 안 봐서 소켓을 또 엶 (초대가 안 먹힌 것처럼 보임)
    final members = ref.watch(
      conversationProvider(widget.conversationId).select((c) => c?.members),
    );
    final peers = ref
        .watch(discoveryControllerProvider)
        .where((p) => !(members?.containsKey(p.peerId) ?? false))
        .toList();
    final registry = ref.read(linkRegistryProvider);
    final web = registry.isWebConversation(widget.conversationId);
    final s = S.of(context);
    // 시트 전체가 스크롤됨: 작은 플로팅 창·큰 글씨에서 빈 상태 그림이나 버튼이 시트 밖으로 넘치지 않게 함
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          Text(
            S.of(context).t('addPeople.title'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            S.of(context).t('addPeople.body'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          // 브라우저는 WebRTC 방에만 들어옴: 이 방이 WebRTC면 여기에, v7 대화면 새 방을 만들고 앱 상대를 그 방으로 초대함
          OutlinedButton.icon(
            icon: const Icon(Icons.add_link),
            label: Text(s.t('secureWeb.open')),
            onPressed: () async {
              final navigator = Navigator.of(context);
              navigator.pop();
              if (navigator.mounted) {
                await showWebConnectionDialog(
                  navigator.context,
                  conversationId: web ? widget.conversationId : null,
                  moveFrom: web ? null : widget.conversationId,
                );
              }
            },
          ),
          if (!web) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              s.t('secureWeb.moveBody'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (peers.isEmpty)
            EmptyState(
              art: EmptyStateArt.invite,
              title: S.of(context).t('empty.addPeopleTitle'),
              body: S.of(context).t('empty.addPeopleBody'),
            ),
          for (final peer in peers)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _picked.contains(peer.peerId),
              onChanged: (on) => setState(() {
                if (on ?? false) {
                  _picked.add(peer.peerId);
                } else {
                  _picked.remove(peer.peerId);
                }
              }),
              title: Text(peer.alias),
              subtitle: Text(peer.detail),
            ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: _picked.isEmpty
                ? null
                : () {
                    final chosen = peers
                        .where((p) => _picked.contains(p.peerId))
                        .toList();
                    final adding = registry.addPeersToRoom(
                      widget.conversationId,
                      chosen,
                    );
                    // WebRTC 방의 자동 초대는 상대가 안 받을 수 있어서 이유를 알림 (v7 방 초대는 예전 그대로)
                    if (web) {
                      final messenger = ScaffoldMessenger.of(context);
                      unawaited(
                        adding.catchError((Object error) {
                          messenger.showSnackBar(
                            SnackBar(
                              duration: const Duration(seconds: 8),
                              content: Text(s.t(autoInviteError(error))),
                            ),
                          );
                        }),
                      );
                    }
                    Navigator.of(context).pop();
                  },
            child: Text(
              _picked.isEmpty
                  ? S.of(context).t('common.add')
                  : S.of(context).t('addPeople.add', {
                      'n': '${_picked.length}',
                    }),
            ),
          ),
        ],
      ),
    );
  }
}
