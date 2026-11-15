part of '../chat_room_screen.dart';

mixin _ChatRoomSearch on _ChatRoomScreenStateBase {
  String? get _currentHit =>
      _searching && _hits.isNotEmpty ? _hits[_hitIndex] : null;

  void _openSearch() => setState(() => _searching = true);

  void _closeSearch() {
    _searchCtrl.clear();
    setState(() {
      _searching = false;
      _hits = const <String>[];
      _hitIndex = 0;
    });
  }

  List<String> _findHits(String query) => ref
      .read(inMemoryStoreProvider)
      .searchMessages(query, conversationId: widget.conversationId)
      .map((r) => r.message.id)
      .toList();

  void _runSearch(String query) {
    final hits = _findHits(query);
    setState(() {
      _hits = hits;
      _hitIndex = hits.isEmpty ? 0 : hits.length - 1; // 최신 히트부터
    });
  }

  // 검색을 열어 둔 채 방 메시지가 바뀌면(새 메시지·소각·삭제) 히트를 다시 구함.
  // 보고 있던 히트가 남아 있으면 그 자리에 머물고, 지워졌으면 가까운 히트로 옮김
  void _refreshSearch() {
    if (!_searching) return;
    final hits = _findHits(_searchCtrl.text);
    if (listEquals(hits, _hits)) return;
    final current = _currentHit;
    final kept = current == null ? -1 : hits.indexOf(current);
    final int next;
    if (hits.isEmpty) {
      next = 0;
    } else if (kept >= 0) {
      next = kept;
    } else if (_hits.isEmpty) {
      next = hits.length - 1; // 처음 생긴 히트는 _runSearch처럼 최신부터
    } else {
      next = _hitIndex.clamp(0, hits.length - 1);
    }
    setState(() {
      _hitIndex = next;
      _hits = hits;
    });
  }

  // Dart의 %는 양수 제수일 때 항상 0 이상이라 음수 보정 없이 양방향으로 순환됨
  void _moveHit(int delta) {
    if (_hits.isEmpty) return;
    setState(() => _hitIndex = (_hitIndex + delta) % _hits.length);
  }
}
