import 'package:flutter/material.dart';

import '../../models/vault_item.dart';
import '../theme.dart';

/// Shows the "what do you want to add?" sheet and returns the chosen kind.
Future<VaultItemKind?> showAddItemSheet(BuildContext context) {
  return showModalBottomSheet<VaultItemKind>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add to your vault',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Everything is encrypted with your master password.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 18),
              _AddOption(
                icon: Icons.language_rounded,
                color: kAccent,
                title: 'Login',
                subtitle: 'Website, username, password and 2FA',
                onTap: () => Navigator.pop(context, VaultItemKind.login),
              ),
              const SizedBox(height: 10),
              _AddOption(
                icon: Icons.key_rounded,
                color: kMint,
                title: 'Passkey',
                subtitle: 'Store relying party and credential metadata',
                onTap: () => Navigator.pop(context, VaultItemKind.passkey),
              ),
              const SizedBox(height: 10),
              _AddOption(
                icon: Icons.shield_moon_rounded,
                color: const Color(0xFFFFC46B),
                title: 'Authenticator',
                subtitle: 'Live 6-digit TOTP codes',
                onTap: () => Navigator.pop(context, VaultItemKind.totp),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _AddOption extends StatelessWidget {
  const _AddOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
