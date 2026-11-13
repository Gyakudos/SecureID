import '../models/totp.dart';
import '../models/vault_item.dart';
import '../util/ids.dart';

/// A password-manager or browser export that SecureID can read.
enum ImportFormat {
  chromium,
  safari,
  firefox,
  bitwarden,
  lastPass,
  onePassword,
  protonPass,
  dashlane,
  keepass,
  nordPass,
  keeper,
  enpass,
  roboForm,
  generic,
}

extension ImportFormatLabel on ImportFormat {
  String get label => switch (this) {
    ImportFormat.chromium => 'Chrome / Edge',
    ImportFormat.safari => 'Safari',
    ImportFormat.firefox => 'Firefox',
    ImportFormat.bitwarden => 'Bitwarden',
    ImportFormat.lastPass => 'LastPass',
    ImportFormat.onePassword => '1Password',
    ImportFormat.protonPass => 'Proton Pass',
    ImportFormat.dashlane => 'Dashlane',
    ImportFormat.keepass => 'KeePass',
    ImportFormat.nordPass => 'NordPass',
    ImportFormat.keeper => 'Keeper',
    ImportFormat.enpass => 'Enpass',
    ImportFormat.roboForm => 'RoboForm',
    ImportFormat.generic => 'Generic CSV',
  };

  /// The CSV columns this format normally uses, shown in the import preview.
  String get columnHint => switch (this) {
    ImportFormat.chromium => 'name, url, username, password, note',
    ImportFormat.safari => 'Title, URL, Username, Password, Notes, OTPAuth',
    ImportFormat.firefox => 'url, username, password',
    ImportFormat.bitwarden =>
      'folder, favorite, type, name, notes, login_uri, login_username, '
          'login_password, login_totp',
    ImportFormat.lastPass =>
      'url, username, password, totp, extra, name, grouping',
    ImportFormat.onePassword =>
      'Title, Url, Username, Password, OTPAuth, Favorite, Tags, Notes',
    ImportFormat.protonPass =>
      'type, name, url, username, password, note, totp, vault',
    ImportFormat.dashlane => 'title, url, username, password, note, otpSecret',
    ImportFormat.keepass => 'Account, Login Name, Password, Web Site, Comments',
    ImportFormat.nordPass => 'name, url, username, password, note',
    ImportFormat.keeper =>
      'Folder, Title, Login, Password, Website Address, Notes',
    ImportFormat.enpass => 'Title, Username, Password, URL, Notes, Category',
    ImportFormat.roboForm => 'Name, Url, MatchUrl, Login, Pwd, Note, Folder',
    ImportFormat.generic =>
      'Recognised title, URL, username and password columns',
  };
}

/// The result of parsing a CSV export.
class PasswordImportResult {
  const PasswordImportResult({
    required this.format,
    required this.items,
    this.skippedRows = 0,
    this.warnings = const <String>[],
    this.hasHeader = true,
  });

  final ImportFormat format;
  final List<VaultItem> items;
  final int skippedRows;
  final List<String> warnings;
  final bool hasHeader;

  int get count => items.length;
}

/// Parses password-manager and browser CSV exports into vault logins.
///
/// The parser understands quoted fields, embedded commas, escaped quotes and
/// multi-line notes, so it can read the raw files that Chrome, Edge, Safari and
/// the popular password managers produce. Format detection is based on the
/// header names, and every row is mapped through the same column resolver, so
/// an unknown export still imports when it uses recognisable headings.
class PasswordCsvImport {
  const PasswordCsvImport._();

  static PasswordImportResult parse(String contents) {
    final text = contents.replaceFirst('\uFEFF', '');
    if (text.trim().isEmpty) {
      return const PasswordImportResult(
        format: ImportFormat.generic,
        items: <VaultItem>[],
        warnings: <String>['The file is empty.'],
      );
    }

    final delimiter = _detectDelimiter(text);
    final rows = _parseRows(text, delimiter);
    if (rows.isEmpty) {
      return const PasswordImportResult(
        format: ImportFormat.generic,
        items: <VaultItem>[],
        warnings: <String>['No rows were found in the file.'],
      );
    }

    final headerRow = rows.first;
    final hasHeader = _looksLikeHeader(headerRow);
    final headers = hasHeader
        ? headerRow.map(_normalizeHeader).toList(growable: false)
        : const <String>[];
    final format = hasHeader ? detectFormat(headers) : ImportFormat.chromium;
    final columns = _ColumnMap(headers);
    final warnings = <String>[];
    if (!hasHeader) {
      warnings.add(
        'No header row was found, so the columns were read in Chrome order '
        '(name, url, username, password, note).',
      );
    }

    final items = <VaultItem>[];
    final seen = <String>{};
    var skipped = 0;
    final dataRows = hasHeader ? rows.skip(1) : rows;

    for (final row in dataRows) {
      if (row.every((value) => value.trim().isEmpty)) {
        skipped++;
        continue;
      }

      final parsed = _itemFromRow(row, columns, hasHeader: hasHeader);
      if (parsed == null) {
        skipped++;
        continue;
      }

      final key = _duplicateKey(parsed);
      if (!seen.add(key)) {
        skipped++;
        continue;
      }
      items.add(parsed);
    }

    if (items.isEmpty && skipped > 0) {
      warnings.add(
        'No logins could be imported. Check that the file is a password CSV '
        'export and not a spreadsheet with different headings.',
      );
    }

    return PasswordImportResult(
      format: format,
      items: items,
      skippedRows: skipped,
      warnings: warnings,
      hasHeader: hasHeader,
    );
  }

  /// Detects the export format from a header row.
  static ImportFormat detectFormat(Iterable<String> headers) {
    final set = headers.map(_normalizeHeader).toSet();
    bool has(String name) => set.contains(name);

    if (has('login uri') ||
        has('login username') ||
        has('login password') ||
        has('login totp')) {
      return ImportFormat.bitwarden;
    }
    if (has('grouping') || has('fav') || has('extra')) {
      return ImportFormat.lastPass;
    }
    if (has('archived') || (has('tags') && has('favorite'))) {
      return ImportFormat.onePassword;
    }
    if (has('username2') || has('otpsecret') || has('otp secret')) {
      return ImportFormat.dashlane;
    }
    if (has('web site') || has('login name')) {
      return ImportFormat.keepass;
    }
    if (has('website address') ||
        has('custom fields') ||
        has('shared folder')) {
      return ImportFormat.keeper;
    }
    if (has('matchurl') || has('rffieldsv2') || has('rffields v2')) {
      return ImportFormat.roboForm;
    }
    if (has('httprealm') ||
        has('formactionorigin') ||
        has('timecreated') ||
        has('time password changed')) {
      return ImportFormat.firefox;
    }
    if (has('cardholdername') || has('card number') || has('cvv')) {
      return ImportFormat.nordPass;
    }
    if (has('category') && has('title') && has('username')) {
      // Enpass writes Title, Username, Password, URL, Notes, Category.
      // Dashlane, which also has a category column, was matched above.
      return ImportFormat.enpass;
    }
    if (has('type') && has('totp')) {
      // Proton Pass exports type, name, url, username, password, note, totp.
      // Bitwarden, LastPass and Dashlane were already matched above.
      return ImportFormat.protonPass;
    }
    if (has('title') && has('url') && has('username') && has('password')) {
      // 1Password was handled above; the remaining Title/URL shape is the
      // Safari (and Apple Passwords) export.
      return has('otpauth') || has('notes')
          ? ImportFormat.safari
          : ImportFormat.generic;
    }
    if (has('name') && has('url') && has('username') && has('password')) {
      return ImportFormat.chromium;
    }
    return ImportFormat.generic;
  }

  static VaultItem? _itemFromRow(
    List<String> row,
    _ColumnMap columns, {
    required bool hasHeader,
  }) {
    String value(List<String> names) {
      final index = columns.indexOf(names);
      if (index == null || index < 0 || index >= row.length) return '';
      return row[index].trim();
    }

    if (!hasHeader) {
      // Chrome's headerless order: name, url, username, password, note.
      return _build(
        title: _at(row, 0),
        username: _at(row, 2),
        password: _at(row, 3),
        url: _at(row, 1),
        notes: _at(row, 4),
        totpSecret: '',
        folder: '',
        favorite: false,
      );
    }

    final type = value(const <String>['type']).toLowerCase();
    // Proton Pass and Bitwarden mark cards and identities with a type column.
    // They hold no login credentials, so they are skipped rather than turned
    // into logins with an empty password.
    if (type == 'card' ||
        type == 'creditcard' ||
        type == 'credit card' ||
        type == 'identity') {
      return null;
    }

    final title = value(const <String>[
      'name',
      'title',
      'account',
      'item name',
    ]);
    final username = value(const <String>[
      'username',
      'login username',
      'user',
      'login name',
      'login',
      'email',
      'account name',
    ]);
    final password = value(const <String>[
      'password',
      'login password',
      'pass',
      'pwd',
    ]);
    var url = value(const <String>[
      'url',
      'login uri',
      'web site',
      'website',
      'website address',
      'uri',
      'login url',
      'site',
    ]);
    var notes = value(const <String>[
      'note',
      'notes',
      'comments',
      'comment',
      'extra',
      'additional info',
    ]);
    final customFields = value(const <String>['custom fields']);
    if (customFields.isNotEmpty) {
      final extra = 'Custom fields:\n$customFields';
      notes = notes.isEmpty ? extra : '$notes\n\n$extra';
    }
    final totpSecret = value(const <String>[
      'totp',
      'login totp',
      'otpauth',
      'otp',
      'otpsecret',
      'otp secret',
      'otp auth',
      '2fa',
      'two factor authentication',
    ]);
    final folder = value(const <String>[
      'folder',
      'grouping',
      'group',
      'category',
      'collection',
      'vault',
      'tags',
      'tag',
    ]);
    final favorite = _truthy(
      value(const <String>['favorite', 'fav', 'starred']),
    );

    final extraUrls = _extraUrls(url);
    url = _firstUrl(url);
    if (extraUrls.isNotEmpty) {
      final extra = 'Other URLs:\n${extraUrls.join('\n')}';
      notes = notes.isEmpty ? extra : '$notes\n\n$extra';
    }

    return _build(
      title: title,
      username: username,
      password: password,
      url: url,
      notes: notes,
      totpSecret: totpSecret,
      folder: folder,
      favorite: favorite,
    );
  }

  static VaultItem? _build({
    required String title,
    required String username,
    required String password,
    required String url,
    required String notes,
    required String totpSecret,
    required String folder,
    required bool favorite,
  }) {
    if (title.isEmpty &&
        username.isEmpty &&
        password.isEmpty &&
        url.isEmpty &&
        notes.isEmpty) {
      return null;
    }

    var resolvedTitle = title.trim();
    if (resolvedTitle.isEmpty) resolvedTitle = _titleFromUrl(url);
    if (resolvedTitle.isEmpty) resolvedTitle = username.trim();
    if (resolvedTitle.isEmpty) resolvedTitle = 'Imported login';

    final tags = folder
        .split(RegExp(r'[,;]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);

    return VaultItem(
      id: newId(),
      kind: VaultItemKind.login,
      title: resolvedTitle,
      username: username.trim(),
      password: password,
      url: url.trim(),
      notes: notes.trim(),
      tags: tags,
      favorite: favorite,
      totp: _parseTotp(totpSecret, title: resolvedTitle, username: username),
    );
  }

  static String _at(List<String> row, int index) =>
      index < row.length ? row[index].trim() : '';

  static bool _truthy(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'y' ||
        normalized == 'favorite';
  }

  static String _duplicateKey(VaultItem item) {
    return '${item.title.trim().toLowerCase()}|'
        '${item.username.trim().toLowerCase()}|'
        '${_urlKey(item.url)}';
  }

  static String _urlKey(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    var candidate = trimmed;
    if (!candidate.contains('://')) candidate = 'https://$candidate';
    final uri = Uri.tryParse(candidate);
    final host = (uri?.host ?? '').toLowerCase();
    if (host.isEmpty) return trimmed.toLowerCase();
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  static String _titleFromUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    var candidate = trimmed;
    if (!candidate.contains('://')) candidate = 'https://$candidate';
    final uri = Uri.tryParse(candidate);
    final host = uri?.host ?? '';
    if (host.isEmpty) return '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  static String _firstUrl(String value) {
    for (final part in value.split(RegExp(r'[\s,]+'))) {
      if (part.trim().isNotEmpty) return part.trim();
    }
    return '';
  }

  static List<String> _extraUrls(String value) {
    final parts = value
        .split(RegExp(r'[\s,]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return parts.length <= 1 ? const <String>[] : parts.sublist(1);
  }

  static TotpData? _parseTotp(
    String raw, {
    required String title,
    required String username,
  }) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    if (value.toLowerCase().startsWith('otpauth://')) {
      final uri = Uri.tryParse(value);
      if (uri == null) return null;
      final secret = (uri.queryParameters['secret'] ?? '')
          .replaceAll(RegExp(r'[\s-]'), '')
          .replaceAll('=', '')
          .toUpperCase();
      if (secret.isEmpty) return null;

      var issuer = uri.queryParameters['issuer']?.trim() ?? '';
      var account = Uri.decodeComponent(
        uri.path.startsWith('/') ? uri.path.substring(1) : uri.path,
      ).trim();
      if (account.contains(':')) {
        final parts = account.split(':');
        if (issuer.isEmpty) issuer = parts.first.trim();
        account = parts.sublist(1).join(':').trim();
      }

      return TotpData(
        issuer: issuer.isEmpty ? title : issuer,
        accountName: account.isEmpty ? username : account,
        secret: secret,
        algorithm: TotpAlgorithmLabel.fromUri(uri.queryParameters['algorithm']),
        digits: int.tryParse(uri.queryParameters['digits'] ?? '') ?? 6,
        period: int.tryParse(uri.queryParameters['period'] ?? '') ?? 30,
      );
    }

    final normalized = value
        .replaceAll(RegExp(r'[\s-]'), '')
        .replaceAll('=', '')
        .toUpperCase();
    if (normalized.length < 8 || !RegExp(r'^[A-Z2-7]+$').hasMatch(normalized)) {
      return null;
    }
    return TotpData(issuer: title, accountName: username, secret: normalized);
  }

  static bool _looksLikeHeader(List<String> row) {
    const known = <String>{
      'name',
      'title',
      'account',
      'url',
      'username',
      'password',
      'login uri',
      'login username',
      'login password',
      'notes',
      'note',
      'login name',
      'login',
      'pwd',
      'web site',
      'website address',
      'matchurl',
      'category',
      'grouping',
      'folder',
      'totp',
      'otpauth',
      'type',
    };
    final normalized = row.map(_normalizeHeader).toSet();
    final matches = normalized.intersection(known).length;
    return matches >= 2 || (matches >= 1 && normalized.contains('password'));
  }

  static String _normalizeHeader(String value) {
    return value
        .replaceAll('\uFEFF', '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[_\-.]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _detectDelimiter(String text) {
    var inQuotes = false;
    var commas = 0;
    var semicolons = 0;
    var tabs = 0;
    for (var index = 0; index < text.length; index++) {
      final character = text[index];
      if (character == '"') {
        if (inQuotes && index + 1 < text.length && text[index + 1] == '"') {
          index++;
          continue;
        }
        inQuotes = !inQuotes;
        continue;
      }
      if (inQuotes) continue;
      if (character == ',') {
        commas++;
      } else if (character == ';') {
        semicolons++;
      } else if (character == '\t') {
        tabs++;
      } else if (character == '\n' || character == '\r') {
        break;
      }
    }
    if (semicolons > commas && semicolons > tabs) return ';';
    if (tabs > commas && tabs > semicolons) return '\t';
    return ',';
  }

  /// RFC 4180-style row parser. Handles quoted fields, doubled quotes,
  /// embedded delimiters and newlines.
  static List<List<String>> _parseRows(String text, String delimiter) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var index = 0;

    void endField() {
      row.add(field.toString());
      field.clear();
    }

    void endRow() {
      endField();
      rows.add(row);
      row = <String>[];
    }

    while (index < text.length) {
      final character = text[index];
      if (inQuotes) {
        if (character == '"') {
          if (index + 1 < text.length && text[index + 1] == '"') {
            field.write('"');
            index += 2;
            continue;
          }
          inQuotes = false;
          index++;
          continue;
        }
        field.write(character);
        index++;
        continue;
      }

      if (character == '"' && field.isEmpty) {
        inQuotes = true;
        index++;
        continue;
      }
      if (character == delimiter) {
        endField();
        index++;
        continue;
      }
      if (character == '\r' || character == '\n') {
        if (character == '\r' &&
            index + 1 < text.length &&
            text[index + 1] == '\n') {
          index++;
        }
        endRow();
        index++;
        continue;
      }
      field.write(character);
      index++;
    }

    if (field.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }
}

class _ColumnMap {
  _ColumnMap(List<String> headers) {
    for (var index = 0; index < headers.length; index++) {
      _indexes.putIfAbsent(headers[index], () => index);
    }
  }

  final Map<String, int> _indexes = <String, int>{};

  int? indexOf(List<String> names) {
    for (final name in names) {
      final index = _indexes[name];
      if (index != null) return index;
    }
    return null;
  }
}
