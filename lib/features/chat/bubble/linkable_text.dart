part of '../message_bubble.dart';

// https?:// 링크를 탭 가능한 밑줄 스팬으로 만들고, 실제로 갈 호스트를 확인받은 뒤 OS 브라우저로 엶 (앱은 fetch 안 함)
// TapGestureRecognizer는 이 State가 소유하고 dispose함
class _LinkableText extends StatefulWidget {
  const _LinkableText({
    required this.text,
    required this.style,
    required this.linkColor,
    this.selectable = false,
    this.onMenu,
  });

  final String text;
  final TextStyle style;
  final Color linkColor;

  // 데스크톱: 마우스로 일부만 끌어 선택·복사 (모바일은 길게 누르기가 동작 시트라 통째 복사만)
  final bool selectable;

  // 선택한 글이 없을 때 우클릭이 여는 말풍선 동작 메뉴 (있으면 선택 영역의 복사 메뉴가 뜸)
  final void Function(Offset at)? onMenu;

  @override
  State<_LinkableText> createState() => _LinkableTextState();
}

class _LinkableTextState extends State<_LinkableText> {
  static final _urlRe = RegExp(
    r'https?://[^\s<>()\[\]]+',
    caseSensitive: false,
  );
  // 양방향 제어·폭 없는 문자가 든 주소는 보이는 곳과 여는 곳이 다를 수 있어 링크로 안 만듦
  static final _hiddenRe = RegExp(r'[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]', unicode: true);
  // 이보다 긴 주소도 링크로 안 만듦: 확인 창의 퓨니코드 계산이 길이 제곱이라 1 MiB 메시지 속 주소 한 번
  // 탭에 UI가 몇 분 멈출 수 있음. 브라우저도 이 길이를 넘는 주소는 대개 거부함
  static const _maxLinkLength = 2048;
  // 문단 하나에 수십 MiB를 통째로 넘기면 SkParagraph 조판이 멈춤 (메시지 복사는 원문 전체)
  static const _maxShownChars = 65536;
  // Flutter 기본 줄바꿈은 한글을 음절마다 끊음('보낼/게요'): 한글과 그 옆 글자·숫자 사이에 단어 결합 문자
  // (U+2060)를 넣어 어절에서만 끊기게 함(CSS keep-all). 화면 글에만 넣고 낭독·복사는 원문
  static final _hangulJoin = RegExp(
    r'(?<=[\uAC00-\uD7A3])(?=[\uAC00-\uD7A3\w])|(?<=\w)(?=[\uAC00-\uD7A3])',
  );

  static const _wordJoiner = kIsWeb ? '\uFEFF' : '\u2060';

  static String _keepWords(String s) => s.replaceAll(_hangulJoin, _wordJoiner);

  // 바뀐 글일 때만 낭독용 원문을 붙임 (한글 없는 메시지는 위젯 구조가 그대로)
  static String? _spoken(String plain, String shown) =>
      shown == plain ? null : plain;

  List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  // 선택 영역은 끌 때만 포커스를 받음: Tab 순서엔 말풍선 하나만 남김
  final FocusNode _selectionFocus = FocusNode(
    debugLabel: 'bubble text',
    skipTraversal: true,
  );
  final _selectionArea = GlobalKey<SelectionAreaState>();
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selectionFocus.addListener(_onFocusChanged);
  }

  // 비웹 데스크톱의 SelectableRegion은 바깥 클릭에도 포커스를 유지하고 첫 시작(lifecycleState == null)엔
  // 포커스를 잃어도 선택을 안 지워서 직접 정리함 (창 전환 inactive 때는 선택 유지)
  void _onFocusChanged() {
    if (_selectionFocus.hasFocus) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    _selectionArea.currentState?.selectableRegion.clearSelection();
    _selected = null;
    OsPrivacy.setSelectionCopy(this, null);
  }

  @override
  void dispose() {
    _selectionFocus.removeListener(_onFocusChanged);
    OsPrivacy.setSelectionCopy(this, null);
    for (final r in _recognizers) {
      r.dispose();
    }
    _selectionFocus.dispose();
    super.dispose();
  }

  // 기본 복사(Clipboard.setData)는 클립보드 기록·클라우드 동기화 제외를 안 거쳐서 통째 복사와 같은 길로 보냄
  // 화면 글에만 넣은 단어 결합 문자(U+2060)는 뺌
  void _copySelection() {
    final selected = _selected;
    if (selected == null) return;
    unawaited(
      OsPrivacy.copySensitive(
        selected.replaceAll(RegExp(r'[\u2060\uFEFF]'), ''),
      ),
    );
  }

  Widget _selectable(Widget text) => Actions(
    actions: <Type, Action<Intent>>{
      CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
        onInvoke: (_) => _copySelection(),
      ),
    },
    child: RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        _MenuClick: GestureRecognizerFactoryWithHandlers<_MenuClick>(
          () => _MenuClick(allowed: () => _selected == null),
          (click) =>
              click.onSecondaryTapUp = (details) =>
                  widget.onMenu?.call(details.globalPosition),
        ),
      },
      child: TapRegion(
        groupId: SelectableRegion,
        onTapOutside: (_) => _selectionFocus.unfocus(),
        child: SelectionArea(
          key: _selectionArea,
          focusNode: _selectionFocus,
          onSelectionChanged: (content) {
            final plain = content?.plainText ?? '';
            _selected = plain.isEmpty ? null : plain;
            OsPrivacy.setSelectionCopy(
              this,
              _selected == null ? null : _copySelection,
            );
          },
          contextMenuBuilder: (context, region) =>
              AdaptiveTextSelectionToolbar.buttonItems(
                anchors: region.contextMenuAnchors,
                buttonItems: [
                  for (final item in region.contextMenuButtonItems)
                    item.type == ContextMenuButtonType.copy
                        ? item.copyWith(
                            onPressed: () {
                              _copySelection();
                              region.hideToolbar();
                            },
                          )
                        : item,
                ],
              ),
          child: text,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers = <TapGestureRecognizer>[];

    final text = widget.text;
    // 긴 글은 안내와 앞부분만 낭독함: 통째로 이름이 되면 스크린 리더가 쓸 수 없음 (전체는 복사로, 화면 글은 그대로).
    // 한계: 상한을 넘는 글 속 링크는 낭독 노드로 따로 안 나감. 필요해지면 스팬별로 나눠 자름
    final head = clipCharacters(text, kSpokenMessageChars);
    final long = head.length == text.length
        ? null
        : '${S.of(context).t('a11y.longMessage')}\n$head';
    final clipped = clipCharacters(text, _maxShownChars);
    final body = clipped.length == text.length ? text : '$clipped…';
    final matches = _urlRe
        .allMatches(clipped)
        .where(
          (m) =>
              m.group(0)!.length <= _maxLinkLength &&
              !_hiddenRe.hasMatch(m.group(0)!),
        )
        .toList();
    if (matches.isEmpty) {
      final shown = _keepWords(body);
      final plain = Text(
        shown,
        semanticsLabel: long ?? _spoken(body, shown),
        style: widget.style,
      );
      return widget.selectable ? _selectable(plain) : plain;
    }

    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in matches) {
      if (m.start > last) {
        final plain = body.substring(last, m.start);
        final shown = _keepWords(plain);
        spans.add(TextSpan(text: shown, semanticsLabel: _spoken(plain, shown)));
      }
      final url = m.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _confirmOpenLink(context, url);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: url,
          style: TextStyle(
            color: widget.linkColor,
            decoration: TextDecoration.underline,
            decorationColor: widget.linkColor,
          ),
          recognizer: recognizer,
        ),
      );
      last = m.end;
    }
    if (last < body.length) {
      final plain = body.substring(last);
      final shown = _keepWords(plain);
      spans.add(TextSpan(text: shown, semanticsLabel: _spoken(plain, shown)));
    }
    final rich = Text.rich(
      TextSpan(style: widget.style, children: spans),
      semanticsLabel: long,
    );
    return widget.selectable ? _selectable(rich) : rich;
  }
}
