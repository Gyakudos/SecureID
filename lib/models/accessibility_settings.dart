/// Display and speech preferences for low-vision users.
///
/// These live outside the encrypted vault so they can be applied before the
/// vault is unlocked, and so a user who cannot read the unlock screen can still
/// enlarge it.
class AccessibilitySettings {
  const AccessibilitySettings({
    this.textScale = 1.0,
    this.readAloud = false,
    this.highContrast = false,
  });

  /// Multiplier applied on top of the system text scale.
  final double textScale;

  /// Speak account summaries when an item is opened, and show read-aloud
  /// buttons throughout the app.
  final bool readAloud;

  /// Use a pure-black, high-contrast palette.
  final bool highContrast;

  static const double normalScale = 1.0;
  static const double largeScale = 1.3;
  static const double extraLargeScale = 1.6;
  static const double hugeScale = 2.0;

  bool get largeText => textScale > normalScale;
  bool get enabled => largeText || readAloud || highContrast;

  String get textScaleLabel => '${(textScale * 100).round()}%';

  /// A short human-readable summary used in settings and the panel.
  String get summary {
    final parts = <String>[
      'Text $textScaleLabel',
      if (readAloud) 'read aloud on',
      if (highContrast) 'high contrast on',
    ];
    return parts.join(' · ');
  }

  AccessibilitySettings copyWith({
    double? textScale,
    bool? readAloud,
    bool? highContrast,
  }) {
    return AccessibilitySettings(
      textScale: textScale ?? this.textScale,
      readAloud: readAloud ?? this.readAloud,
      highContrast: highContrast ?? this.highContrast,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'textScale': textScale,
    'readAloud': readAloud,
    'highContrast': highContrast,
  };

  factory AccessibilitySettings.fromJson(Map<String, dynamic> json) {
    const defaults = AccessibilitySettings();
    final rawScale = json['textScale'];
    final rawReadAloud = json['readAloud'];
    final rawHighContrast = json['highContrast'];
    final scale = rawScale is num ? rawScale.toDouble() : defaults.textScale;
    return AccessibilitySettings(
      textScale: scale.clamp(normalScale, hugeScale).toDouble(),
      readAloud: rawReadAloud is bool ? rawReadAloud : defaults.readAloud,
      highContrast: rawHighContrast is bool
          ? rawHighContrast
          : defaults.highContrast,
    );
  }
}
