/// Which unlock method the lock screen presents first.
enum DefaultLoginMethod { password, deviceUnlock, passwordStyle }

/// The quick-unlock credential used by [DefaultLoginMethod.passwordStyle].
enum PasswordStyle { pin, pattern }

/// Device-local unlock preferences.
///
/// These live outside the encrypted vault because the lock screen needs them
/// before the vault is open, and because they describe this device rather than
/// the synced vault.
class DeviceLoginSettings {
  const DeviceLoginSettings({
    this.method = DefaultLoginMethod.password,
    this.style = PasswordStyle.pin,
  });

  final DefaultLoginMethod method;
  final PasswordStyle style;

  DeviceLoginSettings copyWith({
    DefaultLoginMethod? method,
    PasswordStyle? style,
  }) {
    return DeviceLoginSettings(
      method: method ?? this.method,
      style: style ?? this.style,
    );
  }

  Map<String, dynamic> toJson() => {
    'format': 'secureid-login',
    'version': 1,
    'method': method.name,
    'style': style.name,
  };

  factory DeviceLoginSettings.fromJson(Map<String, dynamic> json) {
    final method = DefaultLoginMethod.values.firstWhere(
      (value) => value.name == json['method'],
      orElse: () => DefaultLoginMethod.password,
    );
    final style = PasswordStyle.values.firstWhere(
      (value) => value.name == json['style'],
      orElse: () => PasswordStyle.pin,
    );
    return DeviceLoginSettings(method: method, style: style);
  }
}
