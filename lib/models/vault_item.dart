import '../util/ids.dart';
import 'passkey.dart';
import 'totp.dart';

enum VaultItemKind { login, passkey, totp }

extension VaultItemKindLabel on VaultItemKind {
  String get label => switch (this) {
    VaultItemKind.login => 'Login',
    VaultItemKind.passkey => 'Passkey',
    VaultItemKind.totp => 'Authenticator',
  };
}

/// One encrypted entry in the vault.
class VaultItem {
  VaultItem({
    required this.id,
    required this.kind,
    required this.title,
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    List<String>? tags,
    this.favorite = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.passkey,
    this.totp,
  }) : tags = tags ?? <String>[],
       createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  VaultItemKind kind;
  String title;
  String username;
  String password;
  String url;
  String notes;
  List<String> tags;
  bool favorite;
  DateTime createdAt;
  DateTime updatedAt;
  PasskeyData? passkey;
  TotpData? totp;

  static VaultItem newLogin() =>
      VaultItem(id: newId(), kind: VaultItemKind.login, title: '');

  static VaultItem newPasskey() => VaultItem(
    id: newId(),
    kind: VaultItemKind.passkey,
    title: '',
    passkey: PasskeyData(),
  );

  static VaultItem newTotp() => VaultItem(
    id: newId(),
    kind: VaultItemKind.totp,
    title: '',
    totp: TotpData(),
  );

  bool get isLogin => kind == VaultItemKind.login;
  bool get isPasskey => kind == VaultItemKind.passkey;
  bool get isTotp => kind == VaultItemKind.totp;

  /// True when this entry carries a usable authenticator secret, whether it is
  /// a standalone authenticator item or a login with 2FA attached.
  bool get hasTotp => totp != null && totp!.secret.trim().isNotEmpty;

  String get subtitle {
    if (isPasskey) {
      final passkey = this.passkey;
      if (passkey == null) return 'Passkey';
      if (passkey.accountName.trim().isNotEmpty) return passkey.accountName;
      return passkey.relyingPartyId;
    }
    if (isTotp) {
      final totp = this.totp;
      if (totp == null) return 'Authenticator';
      return totp.displayLabel;
    }
    if (username.trim().isNotEmpty) return username;
    if (url.trim().isNotEmpty) return url;
    return 'Login';
  }

  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    final haystack = <String>[title, username, url, notes, ...tags];
    final passkey = this.passkey;
    if (passkey != null) {
      haystack.addAll([
        passkey.relyingPartyId,
        passkey.relyingPartyName,
        passkey.accountName,
        passkey.credentialId,
        passkey.userHandle,
      ]);
    }
    final totp = this.totp;
    if (totp != null) {
      haystack.addAll([totp.issuer, totp.accountName, totp.displayLabel]);
    }
    return haystack.any((value) => value.toLowerCase().contains(needle));
  }

  VaultItem copy() => VaultItem(
    id: id,
    kind: kind,
    title: title,
    username: username,
    password: password,
    url: url,
    notes: notes,
    tags: List<String>.of(tags),
    favorite: favorite,
    createdAt: createdAt,
    updatedAt: updatedAt,
    passkey: passkey == null ? null : PasskeyData.fromJson(passkey!.toJson()),
    totp: totp == null ? null : TotpData.fromJson(totp!.toJson()),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'username': username,
    'password': password,
    'url': url,
    'notes': notes,
    'tags': tags,
    'favorite': favorite,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (passkey != null) 'passkey': passkey!.toJson(),
    if (totp != null) 'totp': totp!.toJson(),
  };

  factory VaultItem.fromJson(Map<String, dynamic> json) {
    final rawKind = json['kind'] as String? ?? VaultItemKind.login.name;
    final kind = VaultItemKind.values.firstWhere(
      (value) => value.name == rawKind,
      orElse: () => VaultItemKind.login,
    );
    final rawPasskey = json['passkey'];
    final rawTotp = json['totp'];
    return VaultItem(
      id: json['id'] as String? ?? newId(),
      kind: kind,
      title: json['title'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      url: json['url'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      tags:
          (json['tags'] as List<dynamic>?)?.whereType<String>().toList(
            growable: true,
          ) ??
          <String>[],
      favorite: json['favorite'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      passkey: rawPasskey is Map<String, dynamic>
          ? PasskeyData.fromJson(rawPasskey)
          : rawPasskey is Map
          ? PasskeyData.fromJson(
              rawPasskey.map((key, value) => MapEntry('$key', value)),
            )
          : null,
      totp: rawTotp is Map<String, dynamic>
          ? TotpData.fromJson(rawTotp)
          : rawTotp is Map
          ? TotpData.fromJson(
              rawTotp.map((key, value) => MapEntry('$key', value)),
            )
          : null,
    );
  }
}
