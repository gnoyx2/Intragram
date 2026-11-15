import 'package:flutter/material.dart';

// 네이티브와 브라우저가 같은 번들 글꼴을 사용해 외부 글꼴 요청과 화면별 차이를 없앰.
class AppType {
  const AppType._();

  static double toolbarHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final title = scale.titleMedium!;
    final subtitle = scale.bodySmall!;
    return kToolbarHeight +
        (scaler.scale(title.fontSize!) - title.fontSize!) * title.height! +
        (scaler.scale(subtitle.fontSize!) - subtitle.fontSize!) *
            subtitle.height!;
  }

  static final TextTheme scale =
      const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1.25,
          letterSpacing: -0.3,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.30,
          letterSpacing: -0.2,
        ),
        titleMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1.30,
          letterSpacing: -0.2,
        ),
        titleSmall: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.35,
          letterSpacing: -0.1,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.45),
        bodyMedium: TextStyle(fontSize: 15, height: 1.40),
        bodySmall: TextStyle(fontSize: 13, height: 1.40),
        labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.20,
        ),
        labelMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.20,
          letterSpacing: 0.1,
        ),
        labelSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.20,
          letterSpacing: 0.2,
        ),
      ).apply(
        fontFamily: 'IntragramSans',
        fontFamilyFallback: const ['IntragramEmoji', 'Roboto'],
      );
}
