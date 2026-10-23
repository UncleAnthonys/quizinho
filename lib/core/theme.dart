import 'package:flutter/material.dart';

/// Quizinho look: pitch greens underneath, Brazil canary yellow and flag blue on top.
abstract final class Palette {
  static const pitchDeep = Color(0xFF051F15);
  static const pitch = Color(0xFF0A3A28);
  static const pitchLight = Color(0xFF115238);
  static const card = Color(0xFF0E4631);
  static const cardHigh = Color(0xFF165C41);
  static const line = Color(0x33FFFFFF);
  /// Brazil-shirt gold-yellow — the main accent. Warmer than flag canary so it
  /// sits on the green pitch instead of fighting it.
  static const yellow = Color(0xFFFFCC29);

  /// Deeper amber for bonuses, wildcards and celebrations.
  static const gold = Color(0xFFFFAA00);

  /// Royal blue (crest, Career Path) and a brighter blue that reads on green.
  static const blue = Color(0xFF1F4FBF);
  static const blueBright = Color(0xFF4C8BFF);

  /// Brazil flag green — "correct" actions. Brighter than the pitch so it pops.
  static const green = Color(0xFF00B140);
  static const danger = Color(0xFFFF4B4B);
  static const text = Color(0xFFF4FAF6);
  static const muted = Color(0xFFA3C4B4);

  static const teams = <Color>[
    Color(0xFF4C8BFF), // royal blue (bright)
    Color(0xFFFF4B6E), // red
    Color(0xFFFFFFFF), // white
    Color(0xFFB57CFF), // purple
    Color(0xFF3DFFB0), // mint
    Color(0xFFFF8A3D), // orange
  ];

  static Color team(int colorIndex) => teams[colorIndex % teams.length];

  /// Readable text colour on top of a team colour.
  static Color onTeam(int colorIndex) =>
      team(colorIndex).computeLuminance() > 0.45 ? const Color(0xFF07140E) : Colors.white;
}

abstract final class AppText {
  static const display = 'BarlowCondensed';
  static const body = 'Inter';

  static TextStyle headline(double size, {Color color = Palette.text, FontWeight weight = FontWeight.w900}) =>
      TextStyle(fontFamily: display, fontSize: size, fontWeight: weight, color: color, height: 1.0, letterSpacing: 0.5);

  static TextStyle label(double size, {Color color = Palette.muted}) => TextStyle(
      fontFamily: display, fontSize: size, fontWeight: FontWeight.w700, color: color, letterSpacing: 1.6);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.yellow,
    brightness: Brightness.dark,
    primary: Palette.yellow,
    onPrimary: Palette.pitchDeep,
    secondary: Palette.gold,
    surface: Palette.pitch,
    onSurface: Palette.text,
    error: Palette.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.pitchDeep,
    fontFamily: AppText.body,
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 17, color: Palette.text),
      bodyMedium: TextStyle(fontSize: 15, color: Palette.text),
      bodySmall: TextStyle(fontSize: 13, color: Palette.muted),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.yellow, width: 2),
      ),
      hintStyle: const TextStyle(color: Palette.muted),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Palette.cardHigh,
      contentTextStyle: TextStyle(color: Palette.text, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Palette.pitchDeep : Palette.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Palette.yellow : Palette.card),
    ),
  );
}
