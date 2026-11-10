import 'vault_item.dart';
import 'vault_settings.dart';

/// The plaintext contents of the vault. This object only exists in memory
/// while the vault is unlocked; on disk it is always encrypted.
class VaultData {
  VaultData({
    List<VaultItem>? items,
    VaultSettings? settings,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : items = items ?? <VaultItem>[],
       settings = settings ?? VaultSettings(),
       createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = updatedAt ?? DateTime.now().toUtc();

  List<VaultItem> items;
  VaultSettings settings;
  DateTime createdAt;
  DateTime updatedAt;

  int get loginCount => items.where((item) => item.isLogin).length;
  int get passkeyCount => items.where((item) => item.isPasskey).length;
  int get totpCount => items.where((item) => item.hasTotp).length;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'settings': settings.toJson(),
    'items': items.map((item) => item.toJson()).toList(),
  };

  factory VaultData.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final rawSettings = json['settings'];
    return VaultData(
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => VaultItem.fromJson(
                    item.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : <VaultItem>[],
      settings: rawSettings is Map
          ? VaultSettings.fromJson(
              rawSettings.map((key, value) => MapEntry('$key', value)),
            )
          : null,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }
}
