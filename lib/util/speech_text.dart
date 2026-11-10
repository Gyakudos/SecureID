import '../models/vault_item.dart';
import '../security/totp.dart';

/// Builds spoken descriptions of vault entries.
///
/// Summaries never include passwords or authenticator secrets. A detail read
/// can include them because the user explicitly asked for it from the item
/// screen.
String itemSpeech(VaultItem item, {bool includeSecrets = false}) {
  final parts = <String>[];
  final title = item.title.trim().isEmpty ? item.kind.label : item.title.trim();
  parts.add(title);
  parts.add(item.kind.label);

  switch (item.kind) {
    case VaultItemKind.login:
      if (item.username.trim().isNotEmpty) {
        parts.add('Username ${item.username.trim()}');
      }
      if (includeSecrets && item.password.isNotEmpty) {
        parts.add('Password ${item.password}');
      }
      if (item.url.trim().isNotEmpty) {
        parts.add('Website ${item.url.trim()}');
      }
      break;
    case VaultItemKind.passkey:
      final passkey = item.passkey;
      if (passkey != null) {
        if (passkey.relyingPartyName.trim().isNotEmpty) {
          parts.add('For ${passkey.relyingPartyName.trim()}');
        }
        if (passkey.accountName.trim().isNotEmpty) {
          parts.add('Account ${passkey.accountName.trim()}');
        }
      }
      break;
    case VaultItemKind.totp:
      if (item.totp != null) {
        parts.add('Authenticator for ${item.totp!.displayLabel}');
      }
      break;
  }

  if (item.hasTotp) {
    if (includeSecrets) {
      try {
        parts.add('Current code ${generateTotp(item.totp!).code}');
      } on TotpException {
        parts.add('The authenticator secret is not valid');
      }
    } else {
      parts.add('Has two factor authentication');
    }
  }

  if (includeSecrets && item.notes.trim().isNotEmpty) {
    parts.add('Notes ${item.notes.trim()}');
  }
  if (includeSecrets && item.tags.isNotEmpty) {
    parts.add('Tags ${item.tags.join(', ')}');
  }
  if (item.favorite) {
    parts.add('Favorite');
  }

  return '${parts.join('. ')}.';
}

/// Reads every visible entry without exposing secrets.
String itemsSpeech(Iterable<VaultItem> items) {
  final list = items.toList(growable: false);
  if (list.isEmpty) return 'There are no accounts to read.';
  final buffer = StringBuffer()
    ..write('You have ${list.length} ')
    ..write(list.length == 1 ? 'account. ' : 'accounts. ');
  for (final item in list) {
    buffer
      ..write(itemSpeech(item))
      ..write(' ');
  }
  return buffer.toString().trim();
}
