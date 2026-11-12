import 'package:flutter/material.dart';

import '../../state/vault_controller.dart';
import '../../state/vault_scope.dart';
import '../backup_actions.dart';
import '../theme.dart';
import '../widgets/accessibility_panel.dart';
import '../widgets/brand_mark.dart';
import '../widgets/gradient_background.dart';
import '../widgets/strength_meter.dart';
import 'account_screen.dart';
import 'trusted_device_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _obscure = true;
  String? _localError;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final controller = VaultScope.read(context);
    final password = _password.text;
    if (password.length < VaultController.minMasterPasswordLength) {
      setState(() {
        _localError =
            'Use at least ${VaultController.minMasterPasswordLength} characters.';
      });
      return;
    }
    if (password != _confirm.text) {
      setState(() => _localError = 'The two passwords do not match.');
      return;
    }
    setState(() => _localError = null);
    await controller.createVault(password);
    if (!mounted) return;
    if (controller.error != null) {
      setState(() => _localError = controller.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = VaultScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final error = _localError ?? controller.error;

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandMark(size: 64)),
                    const SizedBox(height: 24),
                    Text(
                      'Create your vault',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'One master password protects every login, passkey and '
                      'authenticator code on this device.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _password,
                            autofocus: true,
                            obscureText: _obscure,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) {
                              if (error != null) {
                                setState(() => _localError = null);
                                controller.clearError();
                              } else {
                                setState(() {});
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'Master password',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _obscure
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          StrengthMeter(password: _password.text),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _confirm,
                            obscureText: _obscure,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _create(),
                            onChanged: (_) =>
                                setState(() => _localError = null),
                            decoration: const InputDecoration(
                              labelText: 'Confirm master password',
                              prefixIcon: Icon(Icons.verified_user_outlined),
                            ),
                          ),
                          if (error != null) ...[
                            const SizedBox(height: 16),
                            _ErrorBanner(message: error),
                          ],
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: controller.isBusy ? null : _create,
                            icon: controller.isBusy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.shield_rounded),
                            label: Text(
                              controller.isBusy
                                  ? 'Creating vault…'
                                  : 'Create secure vault',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _Hint(
                      icon: Icons.key_rounded,
                      title: 'There is no password reset',
                      body:
                          'SecureID cannot recover your master password. Keep a '
                          'backup and store the password somewhere safe.',
                    ),
                    const SizedBox(height: 10),
                    _Hint(
                      icon: Icons.memory_rounded,
                      title: 'Encrypted on disk',
                      body:
                          'Argon2id derives the key and AES-256-GCM seals the '
                          'vault. Nothing is stored in plain text.',
                    ),
                    const SizedBox(height: 22),
                    TextButton.icon(
                      onPressed: controller.isBusy
                          ? null
                          : () => showAccessibilitySheet(context),
                      icon: const Icon(Icons.accessibility_new_rounded),
                      label: const Text('Vision & reading'),
                    ),
                    TextButton.icon(
                      onPressed: controller.isBusy
                          ? null
                          : () => restoreVaultBackup(context, controller),
                      icon: const Icon(Icons.settings_backup_restore_rounded),
                      label: const Text('Restore from an encrypted backup'),
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: controller.isBusy
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const TrustedDeviceScreen(
                                  forceReceiver: true,
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.phonelink_ring_rounded),
                      label: const Text('Receive a vault from a linked phone'),
                    ),
                    if (controller.accountAvailable) ...[
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: controller.isBusy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const AccountScreen(
                                    popWhenVaultAppears: true,
                                  ),
                                ),
                              ),
                        icon: const Icon(Icons.cloud_sync_outlined),
                        label: Text(
                          controller.isSignedIn
                              ? 'Sync with ${controller.accountUser?.displayName ?? "your account"}'
                              : 'Sign in to sync an existing vault',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: kMint),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
