import 'package:flutter/material.dart';

import '../../state/vault_controller.dart';
import '../../state/vault_scope.dart';
import '../backup_actions.dart';
import '../widgets/accessibility_panel.dart';
import '../widgets/brand_mark.dart';
import '../widgets/gradient_background.dart';
import 'account_screen.dart';
import 'link_phone_screen.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final TextEditingController _password = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _obscure = true;
  bool _pinBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_password.text.isEmpty) return;
    final controller = VaultScope.read(context);
    await controller.unlock(_password.text);
    if (!mounted) return;
    if (controller.status != VaultStatus.unlocked) {
      _password
        ..clear()
        ..selection = const TextSelection.collapsed(offset: 0);
      _focus.requestFocus();
    }
  }

  Future<void> _unlockWithPin() async {
    final controller = VaultScope.read(context);
    setState(() => _pinBusy = true);
    await controller.unlockWithPin();
    if (mounted) setState(() => _pinBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = VaultScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final busy = controller.isBusy || _pinBusy;
    final error = controller.error;

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandMark(size: 64)),
                    const SizedBox(height: 24),
                    Text(
                      'Welcome back',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Unlock your vault to continue.',
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
                            focusNode: _focus,
                            obscureText: _obscure,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.go,
                            onSubmitted: (_) => busy ? null : _unlock(),
                            onChanged: (_) {
                              if (error != null) controller.clearError();
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
                          if (error != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.error.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: scheme.error.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    size: 18,
                                    color: scheme.error,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      error,
                                      style: TextStyle(
                                        color: scheme.error,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: busy ? null : _unlock,
                            icon: busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.lock_open_rounded),
                            label: Text(busy ? 'Unlocking…' : 'Unlock vault'),
                          ),
                          if (controller.pinEnabled) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: busy ? null : _unlockWithPin,
                              icon: const Icon(Icons.fingerprint_rounded),
                              label: const Text('Unlock with Windows Hello'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () => showAccessibilitySheet(context),
                      icon: const Icon(Icons.accessibility_new_rounded),
                      label: const Text('Vision & reading'),
                    ),
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () => restoreVaultBackup(context, controller),
                      icon: const Icon(Icons.settings_backup_restore_rounded),
                      label: const Text('Restore from an encrypted backup'),
                    ),
                    const SizedBox(height: 2),
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const LinkPhoneScreen(initialTab: 1),
                              ),
                            ),
                      icon: const Icon(Icons.phonelink_ring_rounded),
                      label: const Text('Receive a vault from a linked phone'),
                    ),
                    if (controller.accountAvailable) ...[
                      const SizedBox(height: 2),
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const AccountScreen(),
                                ),
                              ),
                        icon: Icon(
                          controller.isSignedIn
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_sync_outlined,
                        ),
                        label: Text(
                          controller.isSignedIn
                              ? 'Sync with ${controller.accountUser?.displayName ?? "your account"}'
                              : 'Sign in to sync this vault',
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      controller.pinEnabled
                          ? 'Your master password always works, even if Windows '
                                'Hello is unavailable.'
                          : 'Forgot your master password? The vault can only be '
                                'recovered from a backup you exported earlier.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
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
