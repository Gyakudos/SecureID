/// A stored passkey record.
///
/// SecureID stores the public metadata of a passkey so it can be backed up,
/// audited and moved between devices. The private key never leaves the
/// authenticator that created it.
class PasskeyData {
  PasskeyData({
    this.relyingPartyId = '',
    this.relyingPartyName = '',
    this.accountName = '',
    this.credentialId = '',
    this.userHandle = '',
    this.publicKeyCose = '',
    this.algorithm = -7,
    this.signCount = 0,
    this.discoverable = true,
    this.aaguid = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  /// The relying party identifier, normally a domain such as `github.com`.
  String relyingPartyId;

  /// A friendly name for the relying party.
  String relyingPartyName;

  /// The account this passkey belongs to.
  String accountName;

  /// Base64url credential ID.
  String credentialId;

  /// Base64url user handle (user.id in WebAuthn).
  String userHandle;

  /// Base64-encoded COSE public key.
  String publicKeyCose;

  /// COSE algorithm identifier: -7 ES256, -257 RS256, -8 EdDSA.
  int algorithm;

  /// Signature counter reported by the authenticator.
  int signCount;

  /// Whether this is a discoverable (resident) credential.
  bool discoverable;

  /// Authenticator AAGUID, when known.
  String aaguid;

  DateTime createdAt;

  bool get isValid =>
      relyingPartyId.trim().isNotEmpty &&
      accountName.trim().isNotEmpty &&
      credentialId.trim().isNotEmpty;

  String get algorithmLabel => switch (algorithm) {
    -7 => 'ES256 · P-256',
    -257 => 'RS256 · RSA',
    -8 => 'EdDSA · Ed25519',
    _ => 'COSE $algorithm',
  };

  Map<String, dynamic> toJson() => {
    'relyingPartyId': relyingPartyId,
    'relyingPartyName': relyingPartyName,
    'accountName': accountName,
    'credentialId': credentialId,
    'userHandle': userHandle,
    'publicKeyCose': publicKeyCose,
    'algorithm': algorithm,
    'signCount': signCount,
    'discoverable': discoverable,
    'aaguid': aaguid,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PasskeyData.fromJson(Map<String, dynamic> json) {
    return PasskeyData(
      relyingPartyId: json['relyingPartyId'] as String? ?? '',
      relyingPartyName: json['relyingPartyName'] as String? ?? '',
      accountName: json['accountName'] as String? ?? '',
      credentialId: json['credentialId'] as String? ?? '',
      userHandle: json['userHandle'] as String? ?? '',
      publicKeyCose: json['publicKeyCose'] as String? ?? '',
      algorithm: (json['algorithm'] as num?)?.toInt() ?? -7,
      signCount: (json['signCount'] as num?)?.toInt() ?? 0,
      discoverable: json['discoverable'] as bool? ?? true,
      aaguid: json['aaguid'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }
}
