import 'dart:convert';

/// A device that has completed the SecureID pairing handshake.
///
/// The [trustKey] authenticates the transport only. It can never decrypt the
/// vault: the master password is still required on the receiving device.
class TrustedDevice {
  const TrustedDevice({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.trustKey,
    this.createdAt,
    this.lastUsedAt,
    this.lastAddress,
    this.autoAccept = false,
  });

  final String deviceId;
  final String name;
  final String platform;

  /// 32-byte shared key derived during pairing. Never sent over the network.
  final List<int> trustKey;

  final DateTime? createdAt;
  final DateTime? lastUsedAt;

  /// The last `host:port` this device was reached at, used when discovery is
  /// blocked by the network.
  final String? lastAddress;

  /// When true the receiving side may accept a transfer without an extra
  /// prompt. Defaults to false: every transfer asks first.
  final bool autoAccept;

  static const int trustKeyLength = 32;

  String get platformLabel => switch (platform) {
    'windows' => 'Windows',
    'android' => 'Android',
    'macos' => 'macOS',
    'linux' => 'Linux',
    'ios' => 'iOS',
    _ => platform.isEmpty ? 'Device' : platform,
  };

  TrustedDevice copyWith({
    String? name,
    String? platform,
    List<int>? trustKey,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    String? lastAddress,
    bool? autoAccept,
  }) => TrustedDevice(
    deviceId: deviceId,
    name: name ?? this.name,
    platform: platform ?? this.platform,
    trustKey: trustKey ?? this.trustKey,
    createdAt: createdAt ?? this.createdAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    lastAddress: lastAddress ?? this.lastAddress,
    autoAccept: autoAccept ?? this.autoAccept,
  );

  Map<String, dynamic> toJson() => {
    'id': deviceId,
    'name': name,
    'platform': platform,
    'key': base64Encode(trustKey),
    'createdAt': createdAt?.toUtc().toIso8601String(),
    'lastUsedAt': lastUsedAt?.toUtc().toIso8601String(),
    'address': lastAddress,
    'autoAccept': autoAccept,
  };

  factory TrustedDevice.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final keyText = json['key'] as String? ?? '';
    List<int> key;
    try {
      key = base64Decode(keyText);
    } on FormatException {
      throw const FormatException('Invalid trusted device key.');
    }
    if (id.isEmpty || key.length != trustKeyLength) {
      throw const FormatException('Invalid trusted device record.');
    }
    return TrustedDevice(
      deviceId: id,
      name: json['name'] as String? ?? 'SecureID device',
      platform: json['platform'] as String? ?? 'unknown',
      trustKey: key,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      lastUsedAt: DateTime.tryParse(json['lastUsedAt'] as String? ?? ''),
      lastAddress: json['address'] as String?,
      autoAccept: json['autoAccept'] as bool? ?? false,
    );
  }
}
