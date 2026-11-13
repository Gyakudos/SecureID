import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/device_login.dart';
import '../../security/quick_unlock.dart';
import '../../state/vault_controller.dart';
import '../../state/vault_scope.dart';
import '../backup_actions.dart';
import '../widgets/accessibility_panel.dart';
import '../widgets/brand_mark.dart';
import '../widgets/gradient_background.dart';
import '../widgets/pattern_pad.dart';
import '../widgets/pin_pad.dart';
import 'account_screen.dart';
import 'pair_device_screen.dart';

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

  /// Set when the user picks a different method than the saved default.
  DefaultLoginMethod? _methodOverride;
  bool _autoPrompted = false;
  bool _focusRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = VaultScope.read(context);
    final method = _methodOverride ?? controller.effectiveDefaultLogin;

    if (!_autoPrompted &&
        _methodOverride == null &&
        method == DefaultLoginMethod.deviceUnlock &&
        controller.pinEnabled) {
      _autoPrompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !controller.isBusy) _unlockWithPin();
      });
    }

    if (!_focusRequested && method == DefaultLoginMethod.password) {
      _focusRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
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
    if (!mounted) return;
    setState(() => _pinBusy = false);
    if (controller.status != VaultStatus.unlocked && !controller.pinEnabled) {
      _switchTo(DefaultLoginMethod.password);
    }
  }

  Future<void> _unlockWithQuick(String secret) async {
    final controller = VaultScope.read(context);
    await controller.unlockWithQuick(secret);
    if (!mounted) return;
    if (controller.status == VaultStatus.unlocked) return;
    if (controller.quickUnlockLockedOut) {
      _switchTo(DefaultLoginMethod.password);
    }
  }

  void _switchTo(DefaultLoginMethod method, {bool prompt = false}) {
    setState(() => _methodOverride = method);
    if (method == DefaultLoginMethod.password) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
    if (prompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _unlockWithPin();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = VaultScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final busy = controller.isBusy || _pinBusy;
    final error = controller.error;
    final method = _methodOverride ?? controller.effectiveDefaultLogin;

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
                    switch (method) {
                      DefaultLoginMethod.password => _passwordCard(
                        controller,
                        scheme,
                        busy,
                        error,
                      ),
                      DefaultLoginMethod.deviceUnlock => _deviceCard(
                        controller,
                        scheme,
                        busy,
                        error,
                      ),
                      DefaultLoginMethod.passwordStyle => _quickCard(
                        controller,
                        scheme,
                        busy,
                        error,
                      ),
                    },
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
                                    const PairDeviceScreen(receiveOnly: true),
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
                      controller.pinEnabled || controller.quickUnlockEnabled
                          ? 'Your master password always works, even if the '
                                'quick unlock method is unavailable.'
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

  Widget _passwordCard(
    VaultController controller,
    ColorScheme scheme,
    bool busy,
    String? error,
  ) {
    return _card(
      scheme,
      Column(
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
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _obscure = !_obscure),
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
            _errorBox(error, scheme),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: busy ? null : _unlock,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_open_rounded),
            label: Text(busy ? 'Unlocking…' : 'Unlock vault'),
          ),
          if (controller.pinEnabled) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => _switchTo(
                      DefaultLoginMethod.deviceUnlock,
                      prompt: true,
                    ),
              icon: const Icon(Icons.fingerprint_rounded),
              label: Text(controller.pinUnlockButtonLabel),
            ),
          ],
          if (controller.quickUnlockEnabled &&
              !controller.quickUnlockLockedOut) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => _switchTo(DefaultLoginMethod.passwordStyle),
              icon: Icon(
                controller.passwordStyle == PasswordStyle.pin
                    ? Icons.dialpad_rounded
                    : Icons.gesture_rounded,
              ),
              label: Text(
                controller.passwordStyle == PasswordStyle.pin
                    ? 'Use PIN instead'
                    : 'Use pattern instead',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deviceCard(
    VaultController controller,
    ColorScheme scheme,
    bool busy,
    String? error,
  ) {
    return _card(
      scheme,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.fingerprint_rounded, size: 56, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            controller.pinUnlockButtonLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            controller.pinAvailableHint,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            _errorBox(error, scheme),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: busy ? null : _unlockWithPin,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fingerprint_rounded),
            label: Text(busy ? 'Waiting for confirmation…' : 'Unlock'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: busy
                ? null
                : () => _switchTo(DefaultLoginMethod.password),
            child: const Text('Use master password instead'),
          ),
        ],
      ),
    );
  }

  Widget _quickCard(
    VaultController controller,
    ColorScheme scheme,
    bool busy,
    String? error,
  ) {
    final isPin = controller.passwordStyle == PasswordStyle.pin;
    final width = MediaQuery.sizeOf(context).width;
    final patternSize = math.max(200.0, math.min(280.0, width - 120));
    return _card(
      scheme,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isPin ? 'Enter your PIN' : 'Draw your pattern',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            isPin ? 'Six digits' : 'Connect at least four dots',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          ),
          const SizedBox(height: 18),
          if (isPin)
            Center(
              child: PinPad(enabled: !busy, onCompleted: _unlockWithQuick),
            )
          else
            Center(
              child: PatternPad(
                size: patternSize,
                enabled: !busy,
                onCompleted: (dots) =>
                    _unlockWithQuick(QuickUnlockCrypto.patternSecret(dots)),
              ),
            ),
          if (error != null) ...[
            const SizedBox(height: 12),
            _errorBox(error, scheme),
          ],
          const SizedBox(height: 8),
          Text(
            controller.quickUnlockLockedOut
                ? 'Too many attempts. Unlock with your master password.'
                : '${controller.quickUnlockAttemptsRemaining} '
                      'attempt${controller.quickUnlockAttemptsRemaining == 1 ? '' : 's'} '
                      'left before the master password is required.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: controller.quickUnlockLockedOut
                  ? scheme.error
                  : scheme.onSurfaceVariant,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: busy
                ? null
                : () => _switchTo(DefaultLoginMethod.password),
            child: const Text('Use master password instead'),
          ),
        ],
      ),
    );
  }

  Widget _card(ColorScheme scheme, Widget child) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }

  Widget _errorBox(String message, ColorScheme scheme) {
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
