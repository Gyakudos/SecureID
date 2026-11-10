/// Time-based one-time password metadata.
///
/// The secret is a Base32 string stored inside the encrypted vault. It is only
/// used to derive the current 6-8 digit code; nothing is sent anywhere.
enum TotpAlgorithm { sha1, sha256, sha512 }

extension TotpAlgorithmLabel on TotpAlgorithm {
  String get label => switch (this) {
    TotpAlgorithm.sha1 => 'SHA-1',
    TotpAlgorithm.sha256 => 'SHA-256',
    TotpAlgorithm.sha512 => 'SHA-512',
  };

  String get uriName => switch (this) {
    TotpAlgorithm.sha1 => 'SHA1',
    TotpAlgorithm.sha256 => 'SHA256',
    TotpAlgorithm.sha512 => 'SHA512',
  };

  static TotpAlgorithm fromUri(String? value) {
    switch (value?.toUpperCase()) {
      case 'SHA256':
        return TotpAlgorithm.sha256;
      case 'SHA512':
        return TotpAlgorithm.sha512;
      default:
        return TotpAlgorithm.sha1;
    }
  }
}

class TotpData {
  TotpData({
    this.issuer = '',
    this.accountName = '',
    this.secret = '',
    this.algorithm = TotpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
  });

  /// Service name, e.g. `GitHub`.
  String issuer;

  /// Account label, e.g. `alice@example.com`.
  String accountName;

  /// Base32 secret, normalized to uppercase without spaces or padding.
  String secret;

  TotpAlgorithm algorithm;
  int digits;
  int period;

  bool get isValid =>
      secret.trim().isNotEmpty &&
      digits >= 6 &&
      digits <= 8 &&
      period >= 15 &&
      period <= 120;

  String get displayAccount =>
      accountName.trim().isNotEmpty ? accountName : issuer;

  String get displayLabel {
    final parts = <String>[
      if (issuer.trim().isNotEmpty) issuer.trim(),
      if (accountName.trim().isNotEmpty) accountName.trim(),
    ];
    return parts.isEmpty ? 'Authenticator' : parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
    'issuer': issuer,
    'accountName': accountName,
    'secret': secret,
    'algorithm': algorithm.name,
    'digits': digits,
    'period': period,
  };

  factory TotpData.fromJson(Map<String, dynamic> json) {
    final algorithmName =
        json['algorithm'] as String? ?? TotpAlgorithm.sha1.name;
    return TotpData(
      issuer: json['issuer'] as String? ?? '',
      accountName: json['accountName'] as String? ?? '',
      secret: json['secret'] as String? ?? '',
      algorithm: TotpAlgorithm.values.firstWhere(
        (value) => value.name == algorithmName,
        orElse: () => TotpAlgorithm.sha1,
      ),
      digits: (json['digits'] as num?)?.toInt() ?? 6,
      period: (json['period'] as num?)?.toInt() ?? 30,
    );
  }
}
