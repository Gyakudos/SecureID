import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/security/android_biometric_unlock.dart';
import 'package:secure_id/security/pin_unlock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(AndroidBiometricUnlock.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  AndroidBiometricUnlock build({bool platformSupported = true}) {
    return AndroidBiometricUnlock(platformSupported: platformSupported);
  }

  test('reports availability from the platform channel', () async {
    mockChannel((_) async => true);
    expect(await build().isAvailable(), isTrue);

    mockChannel((_) async => false);
    expect(await build().isAvailable(), isFalse);
  });

  test(
    'is unavailable on other platforms without touching the channel',
    () async {
      mockChannel((_) async => true);
      expect(await build(platformSupported: false).isAvailable(), isFalse);
      expect(calls, isEmpty);
    },
  );

  test('treats a missing plugin as unavailable', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(await build().isAvailable(), isFalse);
  });

  test('wraps the vault key and binds the record to the vault salt', () async {
    final wrapped = Uint8List.fromList(List<int>.generate(60, (i) => i));
    mockChannel((call) async {
      expect(call.method, 'wrap');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['alias'], AndroidBiometricUnlock.keyAlias);
      expect(args['key'], Uint8List.fromList([1, 2, 3, 4]));
      return wrapped;
    });

    final record = await build().wrapVaultKey(
      vaultKey: [1, 2, 3, 4],
      salt: [9, 8, 7],
    );

    expect(record.vaultId, 'CQgH');
    expect(record.wrappedKey, wrapped);
  });

  test('unwraps a stored record through the platform channel', () async {
    final plaintext = Uint8List.fromList(List<int>.generate(32, (i) => i));
    mockChannel((call) async {
      expect(call.method, 'unwrap');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['alias'], AndroidBiometricUnlock.keyAlias);
      expect(args['data'], Uint8List.fromList([4, 5, 6]));
      return plaintext;
    });

    final key = await build().unwrapVaultKey(
      const PinVaultRecord(vaultId: 'salt', wrappedKey: [4, 5, 6]),
    );

    expect(key, plaintext);
  });

  test('maps a dismissed prompt to PinUnlockCancelled', () async {
    mockChannel(
      (_) async => throw PlatformException(code: 'cancelled', message: 'no'),
    );

    await expectLater(
      build().unwrapVaultKey(
        const PinVaultRecord(vaultId: 'salt', wrappedKey: [4, 5, 6]),
      ),
      throwsA(isA<PinUnlockCancelled>()),
    );
  });

  test('maps a key invalidation to a readable PinUnlockException', () async {
    mockChannel(
      (_) async => throw PlatformException(
        code: 'key_invalidated',
        message: 'Biometrics changed on this phone.',
      ),
    );

    await expectLater(
      build().unwrapVaultKey(
        const PinVaultRecord(vaultId: 'salt', wrappedKey: [4, 5, 6]),
      ),
      throwsA(
        isA<PinUnlockException>().having(
          (e) => e.message,
          'message',
          contains('Biometrics changed'),
        ),
      ),
    );
  });

  test('reports a missing plugin during wrap', () async {
    messenger.setMockMethodCallHandler(channel, null);

    await expectLater(
      build().wrapVaultKey(vaultKey: [1], salt: [2]),
      throwsA(isA<PinUnlockException>()),
    );
  });

  test('deletes the Keystore key when the record is cleared', () async {
    mockChannel((_) async => null);

    await build().clearDeviceKey();

    expect(calls.single.method, 'deleteKey');
    expect(
      (calls.single.arguments as Map<Object?, Object?>)['alias'],
      AndroidBiometricUnlock.keyAlias,
    );
  });

  test('clearDeviceKey tolerates a missing plugin', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(build().clearDeviceKey(), completes);
  });

  test('accepts Android-shaped records through the shared envelope', () {
    final wrapped = List<int>.generate(60, (i) => i);
    final record = PinVaultRecord(vaultId: 'vault-salt', wrappedKey: wrapped);

    final restored = PinVaultRecord.decode(record.encode());

    expect(restored.vaultId, 'vault-salt');
    expect(restored.wrappedKey, wrapped);
  });
}
