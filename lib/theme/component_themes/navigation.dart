part of '../component_themes.dart';

// headerBar(Linux): GNOME 헤더바처럼 제목을 가운데 두고, 스크롤해도 그림자 대신 아래 실선 하나
AppBarTheme _appBarTheme(
  ColorScheme scheme, {
  bool headerBar = false,
  bool definedBorders = false,
}) => AppBarTheme(
  backgroundColor: scheme.surface,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: headerBar ? 0 : 1,
  centerTitle: headerBar,
  shape: headerBar || definedBorders
      ? Border(
          bottom: BorderSide(
            color: scheme.outlineVariant,
            width: definedBorders ? AppBorder.defined : AppBorder.hairline,
          ),
        )
      : null,
  titleTextStyle: AppType.scale.titleMedium?.copyWith(color: scheme.onSurface),
  toolbarTextStyle: AppType.scale.bodyMedium?.copyWith(color: scheme.onSurface),
  // 명시하지 않으면 AppBar가 전경색을 스스로 계산해서 iOS에서 아이콘이 흰색으로 뜬 적 있음
  foregroundColor: scheme.onSurface,
  iconTheme: IconThemeData(color: scheme.onSurface),
  actionsIconTheme: IconThemeData(color: scheme.onSurface),
  // 상태바·내비바 아이콘 밝기를 테마로 정함 (SystemChrome을 직접 안 불러도 됨).
  // 브라우저는 상태바 색이 theme-color가 됨: 비우면 엔진이 지워서 주소창이 앱바와 다른 색으로 남음
  systemOverlayStyle:
      (scheme.brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark)
          .copyWith(
            systemNavigationBarColor: Colors.transparent,
            statusBarColor: kIsWeb ? scheme.surface : null,
          ),
);

// iOS는 스와이프 뒤로 가기, Android는 predictive back, 데스크톱(macOS 포함)은 페이드를 씀 (Mac 창에서 옆으로 밀려 들어오는 건 Mac 관례가 아님)
PageTransitionsTheme _pageTransitionsTheme() => PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
    TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
  },
);

// macOS 앱 VoiceOver는 뒤로·닫기 버튼 tooltip을 이름으로 못 읽음 (lib/core/target_platform.dart macOSAppName):
// 아이콘은 Flutter macOS 기본과 같고 같은 문구를 label로만 붙임. Android 브라우저는 반대로 tooltip이 이미
// 이름인데 Flutter가 Android 앱용 label을 또 붙여서 "뒤로 뒤로"로 읽힘: 그림만 둠. Flutter는 웹이면 늘 ←를
// 그려서 iPhone 브라우저만 iOS 앱과 같은 꺾쇠로 바꿈(이름은 tooltip). 나머지는 Flutter 기본 그대로
ActionIconThemeData? _actionIcons(TargetPlatform os) => switch ((kIsWeb, os)) {
  (false, TargetPlatform.macOS) => ActionIconThemeData(
    backButtonIconBuilder: (context) => Icon(
      Icons.arrow_back_ios_new_rounded,
      semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
    ),
    closeButtonIconBuilder: (context) => Icon(
      Icons.close,
      semanticLabel: MaterialLocalizations.of(context).closeButtonTooltip,
    ),
  ),
  (true, TargetPlatform.android) => ActionIconThemeData(
    backButtonIconBuilder: (_) => const Icon(Icons.arrow_back),
    closeButtonIconBuilder: (_) => const Icon(Icons.close),
  ),
  (true, TargetPlatform.iOS) => ActionIconThemeData(
    backButtonIconBuilder: (_) => const Icon(Icons.arrow_back_ios_new_rounded),
  ),
  _ => null,
};
