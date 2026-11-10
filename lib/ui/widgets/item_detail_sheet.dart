import 'package:flutter/material.dart';

import '../../models/totp.dart';
import '../../models/vault_item.dart';
import '../../security/totp.dart';
import '../../state/vault_scope.dart';
import '../../util/speech_text.dart';
import '../screens/item_editor_screen.dart';
import '../theme.dart';
import 'confirm_dialog.dart';
import 'secure_clipboard.dart';
import 'totp_display.dart';

Future<void> showItemDetailSheet(BuildContext context, VaultItem item) {
  final controller = VaultScope.read(context);
  if (controller.accessibility.readAloud && controller.speechAvailable) {
    controller.speak(itemSpeech(item));
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ItemDetailSheet(item: item),
  ).whenComplete(controller.stopSpeaking);
}

class ItemDetailSheet extends StatefulWidget {
  const ItemDetailSheet({super.key, required this.item});

  final VaultItem item;

  @override
  State<ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends State<ItemDetailSheet> {
  bool _revealPassword = false;
  bool _revealSecret = false;

  VaultItem get item => widget.item;

  Future<void> _read({bool includeSecrets = false}) {
    return VaultScope.read(context)
        .speak(itemSpeech(item, includeSecrets: includeSecrets));
  }

  void _copy(String value, String label, int seconds) {
    SecureClipboard.copy(
      context,
      value: value,
      label: label,
      clearAfterSeconds: seconds,
    );
  }

  void _edit() {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute(builder: (_) => ItemEditorScreen(item: item.copy())),
    );
  }

  Future<void> _delete() async {
    final controller = VaultScope.read(context);
    final confirmed = await confirmAction(
      context,
      title: 'Delete ${item.title}?',
      message:
          'This item will be removed from the encrypted vault. '
          'This cannot be undone unless you have a backup.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    await controller.deleteItem(item.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggleFavorite() async {
    final controller = VaultScope.read(context);
    await controller.toggleFavorite(item.id);
    if (mounted) setState(() => item.favorite = !item.favorite);
  }

  @override
  Widget build(BuildContext context) {
    final controller = VaultScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final seconds = controller.settings.clipboardClearSeconds;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _KindBadge(kind: item.kind),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (controller.speechAvailable)
                      IconButton(
                        tooltip: 'Read this account aloud',
                        onPressed: () => _read(),
                        icon: const Icon(Icons.volume_up_rounded),
                      ),
                    IconButton(
                      tooltip: item.favorite
                          ? 'Remove from favorites'
                          : 'Add to favorites',
                      onPressed: _toggleFavorite,
                      icon: Icon(
                        item.favorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: item.favorite ? kMint : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (item.hasTotp)
                  _TotpDetail(
                    data: item.totp!,
                    onCopy: () {
                      try {
                        _copy(generateTotp(item.totp!).code, 'Code', seconds);
                      } on TotpException catch (exception) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(exception.message)),
                        );
                      }
                    },
                  ),
                if (item.isLogin) ...[
                  _DetailRow(
                    label: 'Username',
                    value: item.username,
                    icon: Icons.person_outline_rounded,
                    onCopy: item.username.isEmpty
                        ? null
                        : () => _copy(item.username, 'Username', seconds),
                  ),
                  _DetailRow(
                    label: 'Password',
                    value: item.password,
                    icon: Icons.password_rounded,
                    obscured: !_revealPassword,
                    onReveal: () =>
                        setState(() => _revealPassword = !_revealPassword),
                    onCopy: item.password.isEmpty
                        ? null
                        : () => _copy(item.password, 'Password', seconds),
                  ),
                  _DetailRow(
                    label: 'Website',
                    value: item.url,
                    icon: Icons.link_rounded,
                    onCopy: item.url.isEmpty
                        ? null
                        : () => _copy(item.url, 'Website', seconds),
                  ),
                  if (item.notes.trim().isNotEmpty)
                    _DetailRow(
                      label: 'Notes',
                      value: item.notes,
                      icon: Icons.notes_rounded,
                      multiline: true,
                    ),
                ],
                if (item.isPasskey && item.passkey != null) ...[
                  _DetailRow(
                    label: 'Relying party',
                    value: item.passkey!.relyingPartyId,
                    icon: Icons.language_rounded,
                  ),
                  _DetailRow(
                    label: 'Account',
                    value: item.passkey!.accountName,
                    icon: Icons.person_outline_rounded,
                  ),
                  _DetailRow(
                    label: 'Credential ID',
                    value: item.passkey!.credentialId,
                    icon: Icons.fingerprint_rounded,
                    monospace: true,
                    onCopy: () => _copy(
                      item.passkey!.credentialId,
                      'Credential ID',
                      seconds,
                    ),
                  ),
                  _DetailRow(
                    label: 'Algorithm',
                    value: item.passkey!.algorithmLabel,
                    icon: Icons.functions_rounded,
                  ),
                  _DetailRow(
                    label: 'Signature counter',
                    value: item.passkey!.signCount.toString(),
                    icon: Icons.numbers_rounded,
                  ),
                  _DetailRow(
                    label: 'Discoverable',
                    value: item.passkey!.discoverable ? 'Yes' : 'No',
                    icon: Icons.key_rounded,
                  ),
                ],
                if (item.hasTotp) ...[
                  _DetailRow(
                    label: 'Issuer',
                    value: item.totp!.issuer,
                    icon: Icons.badge_outlined,
                  ),
                  _DetailRow(
                    label: 'Account',
                    value: item.totp!.accountName,
                    icon: Icons.person_outline_rounded,
                  ),
                  _DetailRow(
                    label: 'Secret',
                    value: item.totp!.secret,
                    icon: Icons.key_rounded,
                    monospace: true,
                    obscured: !_revealSecret,
                    onReveal: () =>
                        setState(() => _revealSecret = !_revealSecret),
                    onCopy: () => _copy(item.totp!.secret, 'Secret', seconds),
                  ),
                  _DetailRow(
                    label: 'Algorithm',
                    value:
                        '${item.totp!.algorithm.label} · ${item.totp!.digits} digits · ${item.totp!.period}s',
                    icon: Icons.timer_outlined,
                  ),
                ],
                if (item.tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in item.tags)
                        Chip(
                          label: Text(tag),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                if (controller.speechAvailable) ...[
                  OutlinedButton.icon(
                    onPressed: () => _read(includeSecrets: true),
                    icon: const Icon(Icons.volume_up_rounded, size: 18),
                    label: const Text('Read full details aloud'),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _edit,
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: const Text('Edit'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kDanger,
                          side: BorderSide(
                            color: kDanger.withValues(alpha: 0.5),
                          ),
                        ),
                        onPressed: _delete,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TotpDetail extends StatelessWidget {
  const _TotpDetail({required this.data, required this.onCopy});

  final TotpData data;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: TotpCodeView(data: data, onCopy: onCopy),
          ),
          const Icon(Icons.shield_moon_rounded, color: kMint, size: 22),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
    this.onCopy,
    this.onReveal,
    this.obscured = false,
    this.monospace = false,
    this.multiline = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onCopy;
  final VoidCallback? onReveal;
  final bool obscured;
  final bool monospace;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (value.trim().isEmpty) return const SizedBox.shrink();
    final display = obscured ? '•' * value.length.clamp(6, 28) : value;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: multiline
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  display,
                  style: TextStyle(
                    fontFamily: monospace ? 'monospace' : null,
                    fontSize: monospace ? 12.5 : 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (onReveal != null)
            IconButton(
              tooltip: obscured ? 'Reveal' : 'Hide',
              visualDensity: VisualDensity.compact,
              onPressed: onReveal,
              icon: Icon(
                obscured
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 18,
              ),
            ),
          if (onCopy != null)
            IconButton(
              tooltip: 'Copy',
              visualDensity: VisualDensity.compact,
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded, size: 18),
            ),
        ],
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});

  final VaultItemKind kind;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (kind) {
      VaultItemKind.login => (Icons.language_rounded, kAccent),
      VaultItemKind.passkey => (Icons.key_rounded, kMint),
      VaultItemKind.totp => (
        Icons.shield_moon_rounded,
        const Color(0xFFFFC46B),
      ),
    };
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}
