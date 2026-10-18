import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'design_tokens.dart';

/// Tema MediaVault ("Kaca Pagi" light / "Kaca Malam" dark):
/// sanggahan warna hangat netral, satu aksen Harbor Blue untuk aksi-fokus-
/// seleksi, tipografi Geist, sudut 12-16px. Dark theme scheme-nya sendiri,
/// bukan invert — dark mode menyala lewat ThemeMode.system.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(MoriScheme.light);

  static ThemeData dark() => _build(MoriScheme.dark);

  static ThemeData _build(MoriScheme m) {
    final isDark = m.brightness == Brightness.dark;
    final shadow = isDark ? Colors.transparent : const Color(0x33FFFFFF);

    return ThemeData(
      useMaterial3: true,
      brightness: m.brightness,
      fontFamily: 'Geist',

      colorScheme: ColorScheme(
        brightness: m.brightness,
        primary: m.accentFill,
        onPrimary: m.onAccent,
        secondary: m.accent,
        onSecondary: m.onAccent,
        surface: m.background,
        onSurface: m.ink,
        surfaceContainerHighest: m.surfaceVariant,
        surfaceTint: Colors.transparent,
        error: m.error,
        onError: Colors.white,
        inverseSurface: m.inverseSurface,
        onInverseSurface: m.onInverseSurface,
      ),

      scaffoldBackgroundColor: m.background,

      // Snackbar: pill inverse (ink di light, terang di dark).
      snackBarTheme: SnackBarThemeData(
        backgroundColor: m.inverseSurface,
        contentTextStyle: TextStyle(
          color: m.onInverseSurface,
          fontFamily: 'Geist',
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: m.accentFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MoriRadius.button),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: m.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: m.ink),
        titleTextStyle: TextStyle(
          fontFamily: 'Geist',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: m.ink,
        ),
      ),

      // Field: isi surface, border hairline, fokus aksen (tanpa glow).
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: m.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(
          fontFamily: 'Geist',
          fontSize: MoriText.fieldSize,
          color: m.secondary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MoriRadius.field),
          borderSide: BorderSide(color: m.hairline, width: MoriBorder.field),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MoriRadius.field),
          borderSide: BorderSide(color: m.hairline, width: MoriBorder.field),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MoriRadius.field),
          borderSide: BorderSide(color: m.accent, width: MoriBorder.selected),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MoriRadius.field),
          borderSide: BorderSide(color: m.error, width: MoriBorder.field),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MoriRadius.field),
          borderSide: BorderSide(color: m.error, width: MoriBorder.selected),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MoriRadius.field),
          borderSide: BorderSide(
            color: m.hairline.withValues(alpha: 0.6),
            width: MoriBorder.field,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: m.accentFill,
          foregroundColor: m.onAccent,
          disabledBackgroundColor: m.surfaceVariant,
          disabledForegroundColor: m.faint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MoriRadius.button),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: 'Geist',
            fontSize: MoriText.btnSize,
            fontWeight: FontWeight.w600,
            letterSpacing: MoriText.btnLetterSpacing,
          ),
          animationDuration: const Duration(milliseconds: 120),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: m.accentFill,
          foregroundColor: m.onAccent,
          disabledBackgroundColor: m.surfaceVariant,
          disabledForegroundColor: m.faint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MoriRadius.button),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: 'Geist',
            fontSize: MoriText.btnSize,
            fontWeight: FontWeight.w600,
            letterSpacing: MoriText.btnLetterSpacing,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: m.ink,
          side: BorderSide(color: m.hairline, width: MoriBorder.field),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MoriRadius.button),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: 'Geist',
            fontSize: MoriText.btnSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Switch mengikuti aksen baik di tema mana pun.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return m.faint;
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return m.hairline.withValues(alpha: 0.6);
          }
          if (states.contains(WidgetState.selected)) return m.accentFill;
          return isDark ? m.surfaceVariant : m.hairline;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: m.accent,
          textStyle: const TextStyle(
            fontFamily: 'Geist',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      cardTheme: CardThemeData(
        color: m.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MoriRadius.card),
          side: BorderSide(color: m.hairline, width: MoriBorder.tile),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: m.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MoriRadius.card),
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Geist',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: m.ink,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Geist',
          fontSize: 14,
          height: 1.5,
          color: m.secondary,
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: m.accent,
        linearTrackColor: m.surfaceVariant,
        circularTrackColor: m.surfaceVariant,
      ),

      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(fontFamily: 'Geist', fontSize: 13, color: m.ink),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: m.ink,
          iconSize: 24,
          padding: const EdgeInsets.all(12),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: m.hairline,
        thickness: 1,
        space: 1,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: m.surface,
        selectedColor: m.accentTint,
        labelStyle: TextStyle(
          fontFamily: 'Geist',
          fontSize: MoriText.tileSize,
          fontWeight: FontWeight.w500,
          color: m.ink,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MoriRadius.pill),
          side: BorderSide(color: m.hairline, width: MoriBorder.tile),
        ),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // Bayangan hanya di surface terang; di dunia gelap kedalaman lewat border.
      shadowColor: isDark ? Colors.transparent : shadow,

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
