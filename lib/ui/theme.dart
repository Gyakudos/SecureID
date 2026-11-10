import 'package:flutter/material.dart';

const Color kAccent = Color(0xFF8B7DFF);
const Color kMint = Color(0xFF5EEAD4);
const Color kDanger = Color(0xFFFF6B81);
const Color kBg = Color(0xFF070910);
const Color kBgRaised = Color(0xFF0C1020);
const Color kSurface = Color(0xFF111629);
const Color kSurfaceRaised = Color(0xFF171E35);
const Color kText = Color(0xFFEDEFF7);
const Color kMuted = Color(0xFF9AA3BD);

// High-contrast palette for the vision-accessibility mode.
const Color kHcBg = Color(0xFF000000);
const Color kHcText = Color(0xFFFFFFFF);
const Color kHcMuted = Color(0xFFE8E8E8);
const Color kHcAccent = Color(0xFFFFE45E);
const Color kHcMint = Color(0xFF8BFFE0);
const Color kHcOutline = Color(0xFFA7ADB8);

@immutable
class SecureIdThemeData extends ThemeExtension<SecureIdThemeData> {
  const SecureIdThemeData({required this.highContrast});

  final bool highContrast;

  @override
  SecureIdThemeData copyWith({bool? highContrast}) =>
      SecureIdThemeData(highContrast: highContrast ?? this.highContrast);

  @override
  SecureIdThemeData lerp(ThemeExtension<SecureIdThemeData>? other, double t) {
    if (other is! SecureIdThemeData) return this;
    return t < 0.5 ? this : other;
  }
}

bool isHighContrast(BuildContext context) =>
    Theme.of(context).extension<SecureIdThemeData>()?.highContrast ?? false;

ThemeData buildSecureIdTheme({bool highContrast = false}) {
  final base = ColorScheme.fromSeed(
    seedColor: highContrast ? kHcAccent : kAccent,
    brightness: Brightness.dark,
  );
  final scheme = highContrast
      ? base.copyWith(
          primary: kHcAccent,
          onPrimary: Colors.black,
          primaryContainer: const Color(0xFF4A3F00),
          onPrimaryContainer: Colors.white,
          secondary: kHcMint,
          onSecondary: Colors.black,
          secondaryContainer: const Color(0xFF00483A),
          onSecondaryContainer: Colors.white,
          surface: kHcBg,
          onSurface: kHcText,
          onSurfaceVariant: kHcMuted,
          surfaceContainerLowest: Colors.black,
          surfaceContainerLow: const Color(0xFF080808),
          surfaceContainer: const Color(0xFF101010),
          surfaceContainerHigh: const Color(0xFF1C1C1C),
          surfaceContainerHighest: const Color(0xFF2A2A2A),
          error: const Color(0xFFFF9AA8),
          onError: Colors.black,
          outline: kHcOutline,
          outlineVariant: const Color(0xFF747A86),
          shadow: Colors.black,
          scrim: Colors.black,
        )
      : base.copyWith(
          primary: kAccent,
          onPrimary: const Color(0xFF14102B),
          primaryContainer: const Color(0xFF2A2460),
          onPrimaryContainer: const Color(0xFFE4E0FF),
          secondary: kMint,
          onSecondary: const Color(0xFF00201B),
          secondaryContainer: const Color(0xFF123A35),
          onSecondaryContainer: const Color(0xFFB8FFF3),
          surface: kSurface,
          onSurface: kText,
          onSurfaceVariant: kMuted,
          surfaceContainerLowest: kBg,
          surfaceContainerLow: kBgRaised,
          surfaceContainer: kSurface,
          surfaceContainerHigh: kSurfaceRaised,
          surfaceContainerHighest: const Color(0xFF212A45),
          error: kDanger,
          onError: const Color(0xFF2A0710),
          outline: const Color(0xFF303A52),
          outlineVariant: const Color(0xFF232B40),
          shadow: Colors.black,
          scrim: Colors.black,
        );

  final baseText = ThemeData.dark().textTheme;
  final textTheme = baseText.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    extensions: [SecureIdThemeData(highContrast: highContrast)],
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: kBg,
    textTheme: textTheme.copyWith(
      displaySmall: textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
      ),
      headlineMedium: textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      headlineSmall: textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleLarge: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.45),
      labelLarge: textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      floatingLabelStyle: TextStyle(color: scheme.primary),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.error, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      selectedColor: scheme.primary.withValues(alpha: 0.18),
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: TextStyle(color: scheme.onSurface, fontSize: 13),
      secondaryLabelStyle: TextStyle(color: scheme.primary, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.surfaceContainerHigh,
      contentTextStyle: TextStyle(color: scheme.onSurface),
      actionTextColor: scheme.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: scheme.surfaceContainerHighest,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(color: scheme.onSurface, fontSize: 12),
    ),
  );
}
