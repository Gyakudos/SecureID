import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/models/device_login.dart';

void main() {
  test('defaults to the master password and a PIN style', () {
    const settings = DeviceLoginSettings();
    expect(settings.method, DefaultLoginMethod.password);
    expect(settings.style, PasswordStyle.pin);
  });

  test('copies with individual changes', () {
    const settings = DeviceLoginSettings();
    final next = settings.copyWith(
      method: DefaultLoginMethod.passwordStyle,
      style: PasswordStyle.pattern,
    );
    expect(next.method, DefaultLoginMethod.passwordStyle);
    expect(next.style, PasswordStyle.pattern);
    expect(settings.method, DefaultLoginMethod.password);
  });

  test('round-trips through JSON', () {
    const settings = DeviceLoginSettings(
      method: DefaultLoginMethod.passwordStyle,
      style: PasswordStyle.pattern,
    );
    final json = settings.toJson();
    expect(json['format'], 'secureid-login');
    expect(json['version'], 1);

    final restored = DeviceLoginSettings.fromJson(json);
    expect(restored.method, settings.method);
    expect(restored.style, settings.style);
  });

  test('falls back to safe values for unknown names', () {
    final restored = DeviceLoginSettings.fromJson({
      'method': 'something-else',
      'style': 'unknown',
    });
    expect(restored.method, DefaultLoginMethod.password);
    expect(restored.style, PasswordStyle.pin);
  });
}
