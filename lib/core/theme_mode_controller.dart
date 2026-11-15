import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final themeModeProvider = NotifierProvider<AppThemeMode, ThemeMode>(
  AppThemeMode.new,
);

// Like settings without an enabled vault, this preference stays in the session.
class AppThemeMode extends Notifier<ThemeMode> {
  @override
  ThemeMode build() =>
      switch (kIsWeb ? Uri.base.queryParameters['theme'] : null) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
  void setMode(ThemeMode mode) => state = mode;
}
