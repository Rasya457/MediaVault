import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'core/theme/design_tokens.dart';
import 'features/shell/app_shell.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    // iOS: biarkan SF Pro bawaan sistem; Android/lain: Inter
    final fontFamily = (!kIsWeb && Platform.isIOS) ? null : 'Inter';

    return MaterialApp(
      title: 'MORI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: fontFamily,
        colorScheme: const ColorScheme.light(
          surface: MoriColors.background,
          primary: MoriColors.ink,
          onPrimary: Colors.white,
          secondary: MoriColors.ink,
          onSecondary: Colors.white,
          onSurface: MoriColors.ink,
          surfaceTint: Colors.transparent, // hapus Material3 tint
        ),
        scaffoldBackgroundColor: MoriColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: MoriColors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: MoriColors.ink,
          contentTextStyle: TextStyle(color: MoriColors.surface),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          behavior: SnackBarBehavior.floating,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(elevation: 0),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(elevation: 0),
        ),
      ),
      home: const AppShell(),
    );
  }
}
