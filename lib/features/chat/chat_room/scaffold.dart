part of '../chat_room_screen.dart';

mixin _ChatRoomScaffold
    on
        _ChatRoomScreenStateBase,
        _ChatRoomSearch,
        _ChatRoomDialogs,
        _ChatRoomDragDrop {
  PreferredSizeWidget _appBar(
    Conversation conversation, {
    required bool vaultOn,
  }) {
    return AppBar(
      toolbarHeight: AppType.toolbarHeight(context),
      titleSpacing: 0,
      title: _searching
          ? FieldName(
              controller: _searchCtrl,
              name: S.of(context).t('search.inChat'),
              child: TextField(
                enableIMEPersonalizedLearning: false,
                autofillHints: null,
                controller: _searchCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: S.of(context).t('search.inChat'),
                  border: InputBorder.none,
                ),
                onChanged: _runSearch,
              ),
            )
          : ChatTitle(conversation: conversation),
      actions: _searching
          ? [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: Text(
                    _hits.isEmpty ? '0/0' : '${_hitIndex + 1}/${_hits.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.keyboard_arrow_up,
                  semanticLabel: macOSAppName(
                    S.of(context).t('search.previousHit'),
                  ),
                ),
                tooltip: S.of(context).t('search.previousHit'),
                onPressed: _hits.length < 2 ? null : () => _moveHit(-1),
              ),
              IconButton(
                icon: Icon(
                  Icons.keyboard_arrow_down,
                  semanticLabel: macOSAppName(
                    S.of(context).t('search.nextHit'),
                  ),
                ),
                tooltip: S.of(context).t('search.nextHit'),
                onPressed: _hits.length < 2 ? null : () => _moveHit(1),
              ),
              IconButton(
                icon: Icon(
                  Icons.close,
                  semanticLabel: macOSAppName(S.of(context).t('search.close')),
                ),
                tooltip: S.of(context).t('search.close'),
                onPressed: _closeSearch,
              ),
            ]
          : [
              if (conversation.isRoom
                  ? conversation.members.isNotEmpty
                  : conversation.secure && conversation.sas != null)
                SasButton(
                  conversation: conversation,
                  onTap: () => _showSas(conversation),
                ),
              TtlMenu(conversation: conversation, registry: _registry),
              ChatOverflowMenu(
                conversation: conversation,
                registry: _registry,
                // 남이 연 WebRTC 방(참여자)은 사람을 넣을 수 없어서 메뉴를 감춤
                onAddPeople:
                    _registry.isWebConversation(widget.conversationId) &&
                        !_registry.hostsWebRoom(widget.conversationId)
                    ? null
                    : () => showAddPeopleSheet(
                        context,
                        ref,
                        widget.conversationId,
                      ),
                onEndConversation: _endConversation,
                onSearch: _openSearch,
                onToggleKeep: vaultOn && !conversation.isRoom
                    ? () => ref
                          .read(inMemoryStoreProvider)
                          .setVaultOptOut(
                            widget.conversationId,
                            value: !conversation.vaultOptOut,
                          )
                    : null,
              ),
            ],
    );
  }
}

// 앱바를 독립 watch 스코프로 감싸 conversation 필드가 바뀌어도 앱바만 갱신되게 함
// (build 전체나 메시지 리스트는 안 건드림)
class _ChatAppBarScope extends ConsumerWidget implements PreferredSizeWidget {
  const _ChatAppBarScope({
    required this.conversationId,
    required this.builder,
    required this.toolbarHeight,
  });

  final String conversationId;
  final PreferredSizeWidget Function(
    Conversation conversation, {
    required bool vaultOn,
  })
  builder;
  final double toolbarHeight;

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversation = ref.watch(conversationProvider(conversationId));
    final vaultOn = ref.watch(vaultSettingsProvider.select((s) => s.enabled));
    if (conversation == null) return AppBar();
    return builder(conversation, vaultOn: vaultOn);
  }
}
