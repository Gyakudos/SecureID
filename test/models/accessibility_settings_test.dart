import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/models/accessibility_settings.dart';

void main() {
  test('defaults to standard text with no speech or contrast', () {
    const settings = AccessibilitySettings();
    expect(settings.textScale, 1.0);
    expect(settings.readAloud, isFalse);
    expect(settings.highContrast, isFalse);
    expect(settings.largeText, isFalse);
    expect(settings.enabled, isFalse);
    expect(settings.textScaleLabel, '100%');
  });

  test('round-trips through JSON', () {
    const settings = AccessibilitySettings(
      textScale: AccessibilitySettings.extraLargeScale,
      readAloud: true,
      highContrast: true,
    );

    final restored = AccessibilitySettings.fromJson(settings.toJson());
    expect(restored.textScale, AccessibilitySettings.extraLargeScale);
    expect(restored.readAloud, isTrue);
    expect(restored.highContrast, isTrue);
    expect(restored.summary, contains('160%'));
    expect(restored.summary, contains('read aloud on'));
    expect(restored.summary, contains('high contrast on'));
  });

  test('clamps text scale to the supported range', () {
    expect(
      AccessibilitySettings.fromJson({'textScale': 0.1}).textScale,
      AccessibilitySettings.normalScale,
    );
    expect(
      AccessibilitySettings.fromJson({'textScale': 9}).textScale,
      AccessibilitySettings.hugeScale,
    );
  });

  test('ignores malformed values', () {
    final restored = AccessibilitySettings.fromJson({
      'textScale': 'large',
      'readAloud': 'yes',
      'highContrast': 1,
    });
    expect(restored.textScale, 1.0);
    expect(restored.readAloud, isFalse);
    expect(restored.highContrast, isFalse);
  });
}
