import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/security/vault_crypto.dart';

void main() {
  test('creates an envelope that decrypts with the derived key', () async {
    const plaintext = '{"items":[],"settings":{}}';
    final sealed = await VaultCrypto.create(
      password: 'correct horse battery staple',
      plaintext: plaintext,
      config: VaultKdfConfig.test,
    );

    final envelope = VaultEnvelope.decode(sealed.envelope.encode());
    expect(envelope.salt, hasLength(VaultCrypto.saltLength));
    expect(envelope.memory, VaultKdfConfig.test.memory);
    expect(
      envelope.payload.length,
      greaterThan(VaultCrypto.nonceLength + VaultCrypto.macLength),
    );

    final clear = await VaultCrypto.decrypt(sealed.key, envelope.payload);
    expect(clear, plaintext);
  });

  test('rejects the wrong password', () async {
    final sealed = await VaultCrypto.create(
      password: 'correct horse battery staple',
      plaintext: 'secret',
      config: VaultKdfConfig.test,
    );
    final envelope = VaultEnvelope.decode(sealed.envelope.encode());
    final wrong = await VaultCrypto.deriveKey(
      'incorrect horse battery staple',
      envelope.salt,
      VaultKdfConfig.test,
    );

    expect(
      () => VaultCrypto.decrypt(wrong, envelope.payload),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('rejects tampered ciphertext', () async {
    final sealed = await VaultCrypto.create(
      password: 'correct horse battery staple',
      plaintext: 'secret',
      config: VaultKdfConfig.test,
    );
    final envelope = VaultEnvelope.decode(sealed.envelope.encode());
    final tampered = List<int>.of(envelope.payload);
    tampered[tampered.length - 1] ^= 0x01;

    expect(
      () => VaultCrypto.decrypt(sealed.key, tampered),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('rejects envelopes that are not SecureID vaults', () {
    expect(
      () => VaultEnvelope.decode('{"format":"other"}'),
      throwsA(isA<FormatException>()),
    );
  });
}
