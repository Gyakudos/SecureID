import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Thrown when a Windows DPAPI call fails.
class WindowsDpapiException implements Exception {
  const WindowsDpapiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The Win32 `CRYPTOAPI_BLOB` / `DATA_BLOB` structure.
final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _CryptProtectDataNative = Int32 Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Utf16> szDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  Uint32 dwFlags,
  Pointer<_DataBlob> pDataOut,
);
typedef _CryptProtectDataDart = int Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Utf16> szDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  int dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _CryptUnprotectDataNative = Int32 Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Pointer<Utf16>> ppszDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  Uint32 dwFlags,
  Pointer<_DataBlob> pDataOut,
);
typedef _CryptUnprotectDataDart = int Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Pointer<Utf16>> ppszDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  int dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void>);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void>);

typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

/// Thin wrapper around the Windows Data Protection API (DPAPI).
///
/// `CryptProtectData` seals a buffer with a key derived from the current
/// Windows user profile. The ciphertext can only be opened by the same user on
/// the same machine, which makes it a good place to keep the device key that
/// wraps the vault key for Windows Hello unlock.
///
/// The DLLs are loaded lazily so that importing this file on Android (or in
/// tests on other platforms) never touches `crypt32.dll`.
class WindowsDpapi {
  WindowsDpapi._(
    this._protect,
    this._unprotect,
    this._localFree,
    this._getLastError,
  );

  static WindowsDpapi? _instance;

  static WindowsDpapi get instance => _instance ??= _load();

  static WindowsDpapi _load() {
    final crypt32 = DynamicLibrary.open('crypt32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    return WindowsDpapi._(
      crypt32.lookupFunction<_CryptProtectDataNative, _CryptProtectDataDart>(
        'CryptProtectData',
      ),
      crypt32
          .lookupFunction<_CryptUnprotectDataNative, _CryptUnprotectDataDart>(
            'CryptUnprotectData',
          ),
      kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree'),
      kernel32.lookupFunction<_GetLastErrorNative, _GetLastErrorDart>(
        'GetLastError',
      ),
    );
  }

  /// `CRYPTPROTECT_UI_FORBIDDEN`: never show a DPAPI prompt.
  static const int _uiForbidden = 0x1;

  final _CryptProtectDataDart _protect;
  final _CryptUnprotectDataDart _unprotect;
  final _LocalFreeDart _localFree;
  final _GetLastErrorDart _getLastError;

  /// Encrypts [data] for the current Windows user.
  ///
  /// [entropy] is an optional secondary secret that must be supplied again to
  /// decrypt the result.
  Uint8List protect(Uint8List data, {Uint8List? entropy}) {
    return _call(
      data: data,
      entropy: entropy,
      invoke: (input, entropyBlob, output) => _protect(
        input,
        nullptr,
        entropyBlob,
        nullptr,
        nullptr,
        _uiForbidden,
        output,
      ),
      name: 'CryptProtectData',
    );
  }

  /// Decrypts data previously sealed by [protect].
  Uint8List unprotect(Uint8List data, {Uint8List? entropy}) {
    return _call(
      data: data,
      entropy: entropy,
      invoke: (input, entropyBlob, output) => _unprotect(
        input,
        nullptr,
        entropyBlob,
        nullptr,
        nullptr,
        _uiForbidden,
        output,
      ),
      name: 'CryptUnprotectData',
    );
  }

  Uint8List _call({
    required Uint8List data,
    required Uint8List? entropy,
    required int Function(
      Pointer<_DataBlob> input,
      Pointer<_DataBlob> entropyBlob,
      Pointer<_DataBlob> output,
    )
    invoke,
    required String name,
  }) {
    if (data.isEmpty) {
      throw WindowsDpapiException('$name was called with an empty buffer.');
    }

    final inputBytes = malloc.allocate<Uint8>(data.length);
    final inputBlob = calloc<_DataBlob>();
    final outputBlob = calloc<_DataBlob>();
    Pointer<Uint8> entropyBytes = nullptr;
    Pointer<_DataBlob> entropyBlob = nullptr;

    try {
      inputBytes.asTypedList(data.length).setAll(0, data);
      inputBlob.ref
        ..cbData = data.length
        ..pbData = inputBytes;

      if (entropy != null && entropy.isNotEmpty) {
        entropyBytes = malloc.allocate<Uint8>(entropy.length);
        entropyBytes.asTypedList(entropy.length).setAll(0, entropy);
        entropyBlob = calloc<_DataBlob>();
        entropyBlob.ref
          ..cbData = entropy.length
          ..pbData = entropyBytes;
      }

      final result = invoke(inputBlob, entropyBlob, outputBlob);
      if (result == 0) {
        throw WindowsDpapiException(
          '$name failed (Windows error ${_getLastError()}).',
        );
      }

      final output = outputBlob.ref;
      if (output.pbData == nullptr || output.cbData == 0) {
        throw WindowsDpapiException('$name returned no data.');
      }
      return Uint8List.fromList(output.pbData.asTypedList(output.cbData));
    } finally {
      final outputPointer = outputBlob.ref.pbData;
      if (outputPointer != nullptr) {
        _localFree(outputPointer.cast());
      }
      malloc.free(inputBlob);
      malloc.free(outputBlob);
      malloc.free(inputBytes);
      if (entropyBlob != nullptr) malloc.free(entropyBlob);
      if (entropyBytes != nullptr) malloc.free(entropyBytes);
    }
  }
}
