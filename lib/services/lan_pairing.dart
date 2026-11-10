import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../util/ids.dart';

/// Raised when a phone link cannot be started, reached or completed.
class PairingException implements Exception {
  const PairingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The contents of the QR code shown by the sending device.
///
/// The token is random and single-use. The endpoint is a plain HTTP address on
/// the local network; only the already-encrypted vault envelope travels over it.
class PairingLink {
  const PairingLink({
    required this.endpoint,
    required this.token,
    this.deviceName = '',
  });

  final Uri endpoint;
  final String token;
  final String deviceName;

  Uri toUri() => Uri(
    scheme: 'secureid',
    host: 'pair',
    queryParameters: {
      'u': endpoint.toString(),
      't': token,
      if (deviceName.trim().isNotEmpty) 'n': deviceName.trim(),
    },
  );

  String encode() => toUri().toString();

  /// Parses a scanned or pasted `secureid://pair?...` link.
  static PairingLink? tryParse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'secureid' || uri.host != 'pair') {
      return null;
    }
    final endpointText = uri.queryParameters['u'];
    final token = uri.queryParameters['t'];
    if (endpointText == null || token == null || token.trim().isEmpty) {
      return null;
    }
    final endpoint = Uri.tryParse(endpointText);
    if (endpoint == null ||
        endpoint.scheme != 'http' ||
        endpoint.host.isEmpty) {
      return null;
    }
    return PairingLink(
      endpoint: endpoint,
      token: token,
      deviceName: uri.queryParameters['n'] ?? '',
    );
  }
}

class LanPairingOffer {
  const LanPairingOffer({
    required this.link,
    required this.address,
    required this.expiresAt,
  });

  final PairingLink link;
  final String address;
  final DateTime expiresAt;
}

/// Serves the encrypted vault to one phone on the local network.
///
/// The server only exists while the link screen is open. It exposes:
/// - `GET /health` for a reachability probe.
/// - `GET /vault?token=...` which returns the encrypted envelope exactly once.
class LanPairingServer {
  LanPairingServer({this.ttl = const Duration(minutes: 10)});

  final Duration ttl;

  HttpServer? _server;
  String? _token;
  DateTime? _expiresAt;
  bool _used = false;
  String _deviceName = '';
  Timer? _timer;
  Future<String?> Function()? _readEnvelope;
  void Function()? _onSent;

  bool get isRunning => _server != null;
  bool get wasUsed => _used;
  DateTime? get expiresAt => _expiresAt;

  Future<LanPairingOffer> start({
    required Future<String?> Function() readEnvelope,
    required String deviceName,
    void Function()? onSent,
    InternetAddress? bindAddress,
    String? addressOverride,
  }) async {
    await stop();
    final address = addressOverride ?? await pickLanAddress();
    if (address == null) {
      throw const PairingException(
        'No local network address was found. Connect this device to Wi-Fi or '
        'a LAN and try again.',
      );
    }

    final server = await HttpServer.bind(
      bindAddress ?? InternetAddress.anyIPv4,
      0,
    );
    _server = server;
    _deviceName = deviceName;
    _readEnvelope = readEnvelope;
    _onSent = onSent;
    _used = false;
    _token = newId(32);
    _expiresAt = DateTime.now().add(ttl);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final expires = _expiresAt;
      if (expires != null && DateTime.now().isAfter(expires)) {
        unawaited(stop());
      }
    });
    server.listen(_handle, onError: (Object _) {});

    return LanPairingOffer(
      link: PairingLink(
        endpoint: Uri.parse('http://$address:${server.port}'),
        token: _token!,
        deviceName: deviceName,
      ),
      address: address,
      expiresAt: _expiresAt!,
    );
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    try {
      if (request.method != 'GET') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      if (request.uri.path == '/health') {
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({'app': 'SecureID', 'version': 1, 'device': _deviceName}),
        );
        return;
      }
      if (request.uri.path != '/vault') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (_used) {
        response.statusCode = HttpStatus.gone;
        return;
      }
      final expires = _expiresAt;
      if (expires == null || DateTime.now().isAfter(expires)) {
        response.statusCode = HttpStatus.gone;
        return;
      }
      final token = request.uri.queryParameters['token'] ?? '';
      if (!_constantTimeEquals(token, _token ?? '')) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final envelope = await _readEnvelope?.call();
      if (envelope == null || envelope.trim().isEmpty) {
        response.statusCode = HttpStatus.conflict;
        return;
      }
      _used = true;
      response.headers.contentType = ContentType.text;
      response.write(envelope);
      _onSent?.call();
    } catch (_) {
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      await response.close();
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final server = _server;
    _server = null;
    _token = null;
    _expiresAt = null;
    _readEnvelope = null;
    _onSent = null;
    if (server != null) {
      await server.close(force: true);
    }
  }
}

/// Downloads the encrypted vault from a [LanPairingServer].
class LanPairingClient {
  LanPairingClient({this.timeout = const Duration(seconds: 15)});

  final Duration timeout;

  Future<String> fetchEnvelope(PairingLink link) async {
    final uri = link.endpoint.replace(
      path: '/vault',
      queryParameters: {'token': link.token},
    );
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'text/plain');
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);

      if (response.statusCode == HttpStatus.gone) {
        throw const PairingException(
          'That link has expired or was already used. Show a new QR code on '
          'the other device.',
        );
      }
      if (response.statusCode == HttpStatus.conflict) {
        throw const PairingException(
          'The other device has no vault to send yet.',
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw PairingException(
          'The other device refused the request (${response.statusCode}).',
        );
      }
      if (body.trim().isEmpty) {
        throw const PairingException('The other device sent an empty vault.');
      }
      if (body.length > 32 * 1024 * 1024) {
        throw const PairingException('The received vault is too large.');
      }
      return body;
    } on PairingException {
      rethrow;
    } on TimeoutException {
      throw const PairingException(
        'The other device did not respond. Make sure both devices are on the '
        'same Wi-Fi and try again.',
      );
    } on SocketException {
      throw const PairingException(
        'Could not reach the other device. Check that both devices are on the '
        'same Wi-Fi, that the QR code is still valid, and that the firewall '
        'allows the connection.',
      );
    } catch (error) {
      throw PairingException('Could not receive the vault: $error');
    } finally {
      client.close(force: true);
    }
  }
}

/// Picks the best local IPv4 address for the QR code.
Future<String?> pickLanAddress() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final addresses = <String>[
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (address.type == InternetAddressType.IPv4) address.address,
    ];
    if (addresses.isEmpty) return null;
    return addresses.firstWhere(
      _isPrivateAddress,
      orElse: () => addresses.first,
    );
  } catch (_) {
    return null;
  }
}

bool _isPrivateAddress(String address) {
  final parts = address.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((part) => part == null)) return false;
  final first = parts[0]!;
  final second = parts[1]!;
  if (first == 10) return true;
  if (first == 192 && second == 168) return true;
  if (first == 172 && second >= 16 && second <= 31) return true;
  return false;
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var index = 0; index < a.length; index++) {
    difference |= a.codeUnitAt(index) ^ b.codeUnitAt(index);
  }
  return difference == 0;
}
