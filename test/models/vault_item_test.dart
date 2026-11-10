import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/models/totp.dart';
import 'package:secure_id/models/vault_data.dart';
import 'package:secure_id/models/vault_item.dart';
import 'package:secure_id/models/vault_settings.dart';

void main() {
  test('round-trips a login item', () {
    final item = VaultItem.newLogin()
      ..title = 'GitHub'
      ..username = 'alice'
      ..password = 'hunter2'
      ..url = 'https://github.com'
      ..notes = 'Work account'
      ..tags = ['work', 'dev']
      ..favorite = true;

    final restored = VaultItem.fromJson(item.toJson());
    expect(restored.id, item.id);
    expect(restored.kind, VaultItemKind.login);
    expect(restored.title, 'GitHub');
    expect(restored.username, 'alice');
    expect(restored.password, 'hunter2');
    expect(restored.url, 'https://github.com');
    expect(restored.tags, ['work', 'dev']);
    expect(restored.favorite, isTrue);
  });

  test('round-trips passkey metadata', () {
    final item = VaultItem.newPasskey()
      ..title = 'GitHub passkey'
      ..passkey!.relyingPartyId = 'github.com'
      ..passkey!.accountName = 'alice'
      ..passkey!.credentialId = 'abc123';

    final restored = VaultItem.fromJson(item.toJson());
    expect(restored.kind, VaultItemKind.passkey);
    expect(restored.passkey!.relyingPartyId, 'github.com');
    expect(restored.passkey!.credentialId, 'abc123');
    expect(restored.passkey!.algorithm, -7);
  });

  test('round-trips TOTP metadata', () {
    final item = VaultItem.newTotp()
      ..title = 'GitHub'
      ..totp!.issuer = 'GitHub'
      ..totp!.accountName = 'alice'
      ..totp!.secret = 'JBSWY3DPEHPK3PXP'
      ..totp!.algorithm = TotpAlgorithm.sha512
      ..totp!.digits = 8
      ..totp!.period = 60;

    final restored = VaultItem.fromJson(item.toJson());
    expect(restored.kind, VaultItemKind.totp);
    expect(restored.totp!.secret, 'JBSWY3DPEHPK3PXP');
    expect(restored.totp!.algorithm, TotpAlgorithm.sha512);
    expect(restored.totp!.digits, 8);
    expect(restored.totp!.period, 60);
  });

  test('a login can carry its own 2FA secret', () {
    final item = VaultItem.newLogin()
      ..title = 'GitHub'
      ..username = 'alice'
      ..password = 'hunter2';
    expect(item.hasTotp, isFalse);

    item.totp = TotpData(
      issuer: 'GitHub',
      accountName: 'alice',
      secret: 'JBSWY3DPEHPK3PXP',
    );

    expect(item.kind, VaultItemKind.login);
    expect(item.hasTotp, isTrue);

    final restored = VaultItem.fromJson(item.toJson());
    expect(restored.kind, VaultItemKind.login);
    expect(restored.hasTotp, isTrue);
    expect(restored.totp!.secret, 'JBSWY3DPEHPK3PXP');

    final cleared = VaultItem.fromJson(item.toJson())..totp = null;
    expect(cleared.hasTotp, isFalse);
  });

  test('counts 2FA codes across logins and authenticator items', () {
    final login = VaultItem.newLogin()
      ..totp = TotpData(secret: 'JBSWY3DPEHPK3PXP');
    final standalone = VaultItem.newTotp()..totp!.secret = 'JBSWY3DPEHPK3PXP';
    final plainLogin = VaultItem.newLogin();
    final data = VaultData(items: [login, standalone, plainLogin]);
    expect(data.totpCount, 2);
  });

  test('search matches TOTP and passkey fields', () {
    final totp = VaultItem.newTotp()
      ..title = 'Mail'
      ..totp!.issuer = 'Example Corp'
      ..totp!.accountName = 'alice@example.com';
    expect(totp.matches('example corp'), isTrue);
    expect(totp.matches('alice@'), isTrue);
    expect(totp.matches('nope'), isFalse);

    final passkey = VaultItem.newPasskey()
      ..title = 'Bank'
      ..passkey!.relyingPartyId = 'bank.example';
    expect(passkey.matches('bank.example'), isTrue);
  });

  test('settings survive a JSON round-trip', () {
    final settings = VaultSettings()
      ..autoLockMinutes = 15
      ..clipboardClearSeconds = 60
      ..generatorLength = 32
      ..pinUnlockEnabled = true;

    final restored = VaultSettings.fromJson(settings.toJson());
    expect(restored.autoLockMinutes, 15);
    expect(restored.clipboardClearSeconds, 60);
    expect(restored.generatorLength, 32);
    expect(restored.pinUnlockEnabled, isTrue);
  });
}
