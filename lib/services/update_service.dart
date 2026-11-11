import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_version.dart';
import '../models/app_update.dart';

/// A failed update check with a message suitable for showing to the user.
class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Looks up the newest published release.
abstract class UpdateService {
  Future<AppUpdate?> fetchLatest();
}

/// Reads the latest release from the public GitHub API.
///
/// Only public metadata is fetched: the release tag, notes and asset links.
/// No vault data, account details or device identifiers are sent, and the
/// request is only made when the user asks for an update check.
class GitHubUpdateService implements UpdateService {
  GitHubUpdateService({
    http.Client? client,
    this.owner = updateRepositoryOwner,
    this.repo = updateRepositoryName,
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String owner;
  final String repo;
  final Duration timeout;

  @override
  Future<AppUpdate?> fetchLatest() async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/$owner/$repo/releases/latest',
    );
    http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
              'User-Agent': 'SecureID/$appVersion',
            },
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const UpdateException(
        'GitHub took too long to answer. Check your connection and try again.',
      );
    } on SocketException {
      throw const UpdateException(
        'Could not reach GitHub. Check your connection and try again.',
      );
    } on http.ClientException {
      throw const UpdateException(
        'Could not reach GitHub. Check your connection and try again.',
      );
    } catch (_) {
      throw const UpdateException(
        'Could not reach GitHub. Check your connection and try again.',
      );
    }

    // A repository with no published release yet answers 404.
    if (response.statusCode == 404) return null;
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw const UpdateException(
        'GitHub is rate limiting update checks right now. Try again in a '
        'little while.',
      );
    }
    if (response.statusCode != 200) {
      throw UpdateException(
        'GitHub returned an unexpected response (${response.statusCode}).',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Release payload was not an object.');
      }
      return AppUpdate.fromJson(decoded);
    } on FormatException {
      throw const UpdateException(
        'The release information could not be read. Try again later.',
      );
    }
  }
}
