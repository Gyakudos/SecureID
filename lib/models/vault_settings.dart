/// Preferences that travel with the encrypted vault.
class VaultSettings {
  VaultSettings({
    this.autoLockMinutes = 5,
    this.clipboardClearSeconds = 30,
    this.lockOnBackground = true,
    this.generatorLength = 20,
    this.generatorUpper = true,
    this.generatorLower = true,
    this.generatorDigits = true,
    this.generatorSymbols = true,
    this.generatorExcludeAmbiguous = false,
    this.pinUnlockEnabled = false,
  });

  /// 0 means never auto-lock.
  int autoLockMinutes;

  /// 0 means never clear the clipboard.
  int clipboardClearSeconds;

  bool lockOnBackground;
  int generatorLength;
  bool generatorUpper;
  bool generatorLower;
  bool generatorDigits;
  bool generatorSymbols;
  bool generatorExcludeAmbiguous;

  /// Whether the Windows Hello / PIN unlock record is enabled. This is only
  /// meaningful on Windows; other platforms ignore it.
  bool pinUnlockEnabled;

  VaultSettings copy() => VaultSettings(
    autoLockMinutes: autoLockMinutes,
    clipboardClearSeconds: clipboardClearSeconds,
    lockOnBackground: lockOnBackground,
    generatorLength: generatorLength,
    generatorUpper: generatorUpper,
    generatorLower: generatorLower,
    generatorDigits: generatorDigits,
    generatorSymbols: generatorSymbols,
    generatorExcludeAmbiguous: generatorExcludeAmbiguous,
    pinUnlockEnabled: pinUnlockEnabled,
  );

  Map<String, dynamic> toJson() => {
    'autoLockMinutes': autoLockMinutes,
    'clipboardClearSeconds': clipboardClearSeconds,
    'lockOnBackground': lockOnBackground,
    'generatorLength': generatorLength,
    'generatorUpper': generatorUpper,
    'generatorLower': generatorLower,
    'generatorDigits': generatorDigits,
    'generatorSymbols': generatorSymbols,
    'generatorExcludeAmbiguous': generatorExcludeAmbiguous,
    'pinUnlockEnabled': pinUnlockEnabled,
  };

  factory VaultSettings.fromJson(Map<String, dynamic> json) {
    final defaults = VaultSettings();
    return VaultSettings(
      autoLockMinutes:
          (json['autoLockMinutes'] as num?)?.toInt() ??
          defaults.autoLockMinutes,
      clipboardClearSeconds:
          (json['clipboardClearSeconds'] as num?)?.toInt() ??
          defaults.clipboardClearSeconds,
      lockOnBackground:
          json['lockOnBackground'] as bool? ?? defaults.lockOnBackground,
      generatorLength:
          (json['generatorLength'] as num?)?.toInt() ??
          defaults.generatorLength,
      generatorUpper:
          json['generatorUpper'] as bool? ?? defaults.generatorUpper,
      generatorLower:
          json['generatorLower'] as bool? ?? defaults.generatorLower,
      generatorDigits:
          json['generatorDigits'] as bool? ?? defaults.generatorDigits,
      generatorSymbols:
          json['generatorSymbols'] as bool? ?? defaults.generatorSymbols,
      generatorExcludeAmbiguous:
          json['generatorExcludeAmbiguous'] as bool? ??
          defaults.generatorExcludeAmbiguous,
      pinUnlockEnabled:
          json['pinUnlockEnabled'] as bool? ?? defaults.pinUnlockEnabled,
    );
  }
}
