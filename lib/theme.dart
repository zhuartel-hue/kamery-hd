import 'package:flutter/material.dart';

/// Paleta „ocean”: głęboki granat, turkus i błękit, koralowy akcent.
class Ocean {
  static const abyss = Color(0xFF061423); // tło (ciemny motyw)
  static const deep = Color(0xFF0B2236); // karty
  static const deepHigh = Color(0xFF123150); // pola, wyróżnienia
  static const line = Color(0xFF1C3D5C);

  static const aqua = Color(0xFF22D3EE);
  static const lagoon = Color(0xFF06B6D4);
  static const azure = Color(0xFF3B82F6);
  static const coral = Color(0xFFFF7A59);
  static const live = Color(0xFF34D399);

  static const foam = Color(0xFFE6F4FF); // tekst na ciemnym
  static const mist = Color(0xFF8FB3CC); // tekst pomocniczy

  static const mist50 = Color(0xFFF2F8FC); // tło (jasny motyw)
  static const ink = Color(0xFF0A2540);

  /// Główny gradient: przyciski, ikona, akcenty.
  static const gradient = LinearGradient(
    colors: [lagoon, azure],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

const _font = 'PlusJakartaSans';

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Ocean.lagoon,
    brightness: brightness,
  ).copyWith(
    primary: dark ? Ocean.aqua : const Color(0xFF0E7490),
    onPrimary: dark ? Ocean.abyss : Colors.white,
    primaryContainer: dark ? const Color(0xFF0E3A52) : const Color(0xFFD5F3FA),
    onPrimaryContainer: dark ? Ocean.foam : Ocean.ink,
    secondary: Ocean.azure,
    secondaryContainer: dark ? const Color(0xFF0E3A52) : const Color(0xFFD5F3FA),
    onSecondaryContainer: dark ? Ocean.aqua : const Color(0xFF0E7490),
    tertiary: Ocean.coral,
    error: const Color(0xFFFF6B6B),
    surface: dark ? Ocean.abyss : Ocean.mist50,
    onSurface: dark ? Ocean.foam : Ocean.ink,
    onSurfaceVariant: dark ? Ocean.mist : const Color(0xFF52708A),
    surfaceContainerLowest: dark ? const Color(0xFF040E19) : Colors.white,
    surfaceContainerLow: dark ? Ocean.deep : Colors.white,
    surfaceContainer: dark ? Ocean.deep : const Color(0xFFEAF3F9),
    surfaceContainerHigh: dark ? Ocean.deepHigh : const Color(0xFFE1EEF6),
    surfaceContainerHighest: dark ? const Color(0xFF173A5C) : const Color(0xFFD7E7F2),
    outline: dark ? Ocean.line : const Color(0xFFC3D7E5),
    outlineVariant: dark ? Ocean.line : const Color(0xFFD7E5EF),
  );

  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: _font, brightness: brightness);
  final text = base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: _font,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: dark ? 0.6 : 1)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh.withValues(alpha: dark ? 0.7 : 1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      floatingLabelStyle: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
      prefixIconColor: scheme.onSurfaceVariant,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.error, width: 1.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: rounded,
        textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: rounded,
        side: BorderSide(color: scheme.outline),
        textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w600),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
        shape: WidgetStatePropertyAll(rounded),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: _font, fontWeight: FontWeight.w600)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? Ocean.deepHigh : Ocean.ink,
      contentTextStyle: const TextStyle(fontFamily: _font, color: Ocean.foam),
      shape: rounded,
    ),
    listTileTheme: ListTileThemeData(
      shape: rounded,
      iconColor: scheme.onSurfaceVariant,
      selectedColor: scheme.primary,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6), space: 1),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
  );
}

/// Przycisk z gradientem oceanu (główne akcje).
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.onPressed, required this.label, this.icon, this.height = 52});

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: Ocean.gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (enabled)
              BoxShadow(color: Ocean.lagoon.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6)),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: SizedBox(
              height: height,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 8)],
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.only(right: icon != null ? 4 : 0),
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15, fontFamily: _font)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mała etykieta producenta.
class BrandChip extends StatelessWidget {
  const BrandChip({super.key, required this.hikvision});
  final bool hikvision;

  @override
  Widget build(BuildContext context) {
    final color = hikvision ? const Color(0xFFFF8A8A) : const Color(0xFF7CB8FF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        hikvision ? 'HIKVISION' : 'DAHUA',
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8),
      ),
    );
  }
}
