import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_session.dart';

/// A device that has signed in to the same SecureID account.
class LinkedDevice {
  const LinkedDevice({
    required this.deviceId,
    required this.name,
    required this.platform,
    this.lastSeen,
    this.createdAt,
    this.isThisDevice = false,
  });

  final String deviceId;
  final String name;
  final String platform;
  final DateTime? lastSeen;
  final DateTime? createdAt;
  final bool isThisDevice;

  LinkedDevice copyWith({bool? isThisDevice}) => LinkedDevice(
    deviceId: deviceId,
    name: name,
    platform: platform,
    lastSeen: lastSeen,
    createdAt: createdAt,
    isThisDevice: isThisDevice ?? this.isThisDevice,
  );

  String get platformLabel => switch (platform) {
    'windows' => 'Windows',
    'android' => 'Android',
    'macos' => 'macOS',
    'linux' => 'Linux',
    'ios' => 'iOS',
    _ => platform.isEmpty ? 'Device' : platform,
  };
}

/// Tracks the devices linked to one account.
abstract class DeviceRegistry {
  Future<LinkedDevice> register({
    required String deviceId,
    required String name,
    required String platform,
  });

  Future<List<LinkedDevice>> list();

  Future<void> remove(String deviceId);
}

/// Stores the device list in the `devices` table, scoped by row-level security.
class SupabaseDeviceRegistry implements DeviceRegistry {
  SupabaseDeviceRegistry(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AccountException('Sign in before managing linked devices.');
    }
    return id;
  }

  @override
  Future<LinkedDevice> register({
    required String deviceId,
    required String name,
    required String platform,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final row = await _client
        .from('devices')
        .upsert({
          'user_id': _userId,
          'device_id': deviceId,
          'name': name,
          'platform': platform,
          'last_seen': now,
        }, onConflict: 'user_id,device_id')
        .select()
        .single();
    return _map(row);
  }

  @override
  Future<List<LinkedDevice>> list() async {
    final rows = await _client
        .from('devices')
        .select()
        .order('last_seen', ascending: false);
    return [for (final row in rows) _map(row)];
  }

  @override
  Future<void> remove(String deviceId) async {
    await _client.from('devices').delete().eq('device_id', deviceId);
  }

  LinkedDevice _map(Map<String, dynamic> row) {
    return LinkedDevice(
      deviceId: row['device_id'] as String? ?? '',
      name: row['name'] as String? ?? 'SecureID device',
      platform: row['platform'] as String? ?? 'unknown',
      lastSeen: DateTime.tryParse(row['last_seen'] as String? ?? ''),
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
    );
  }
}
