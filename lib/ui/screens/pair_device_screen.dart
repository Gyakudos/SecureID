import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/trusted_device.dart';
import '../../security/trusted_pairing.dart';
import '../../services/trusted_pairing_transport.dart';
import '../../state/vault_controller.dart';
import '../../state/vault_scope.dart';
import '../scanner/raw_qr_scanner_screen.dart';
import '../theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/gradient_background.dart';
import '../widgets/trusted_pairing_widgets.dart';

/// Pairs one device at a time without touching the existing trusted list.
///
/// A computer has no camera, so it always acts as the receiver and shows the
/// QR code. A phone can scan that code, or show a code of its own when it needs
/// to receive a vault. Receiving an update from an already paired device uses
/// the same receiver without creating a new pairing.
class PairDeviceScreen extends StatefulWidget {
  const PairDeviceScreen({super.key, this.receiveOnly = false});

  /// Skips the scan option and goes straight to the receiver. Used by the
  /// setup, unlock and "Receive updates" flows.
  final bool receiveOnly;

  @override
  State<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends State<PairDeviceScreen> {
  final TrustedPairingReceiver _receiver = TrustedPairingReceiver();
  final TrustedPairingSender _sender = TrustedPairingSender();

  TrustPairingOffer? _offer;
  Timer? _countdown;
  Duration _remaining = Duration.zero;

  bool _startingReceiver = false;
  bool _showReceiver = false;
  String? _receiveError;
  String? _pairedWith;
  bool _pairedBySending = false;

  bool _pairing = false;
  String? _pairError;

  bool get _isPhone => Platform.isAndroid;
  bool get _receiverMode => !_isPhone || widget.receiveOnly || _showReceiver;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_receiverMode) {
        unawaited(_startReceiver());
      }
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    unawaited(_receiver.stop());
    super.dispose();
  }

  Future<void> _startReceiver() async {
    final controller = VaultScope.read(context);
    final identity = await controller.ensureDeviceIdentity();
    if (!mounted) return;
    if (identity == null) {
      setState(() {
        _receiveError =
            'This build cannot create a device identity, so it cannot pair.';
      });
      return;
    }

    setState(() {
      _startingReceiver = true;
      _receiveError = null;
      _offer = null;
      _pairedWith = null;
      _pairedBySending = false;
    });

    try {
      final offer = await _receiver.start(
        deviceId: identity.id,
        deviceName: identity.name,
        platform: identity.platform,
        findTrusted: controller.findTrustedDevice,
        remember: controller.rememberTrustedDevice,
        onConfirm: _confirmReceive,
        onEnvelope: _importReceived,
      );
      if (!mounted) {
        await _receiver.stop();
        return;
      }
      setState(() {
        _offer = offer;
        _startingReceiver = false;
        _remaining = offer.expiresAt.difference(DateTime.now());
      });
      _startCountdown();
    } on TrustedTransferException catch (exception) {
      if (!mounted) return;
      setState(() {
        _startingReceiver = false;
        _receiveError = exception.message;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _startingReceiver = false;
        _receiveError = 'Could not start receiving: $exception';
      });
    }
  }

  void _startCountdown() {
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      final offer = _offer;
      if (offer == null) return;
      final left = offer.expiresAt.difference(DateTime.now());
      if (!mounted) return;
      if (left.isNegative || left == Duration.zero) {
        _countdown?.cancel();
        _countdown = null;
        setState(() {
          _remaining = Duration.zero;
          _offer = null;
        });
        unawaited(_receiver.stop());
      } else {
        setState(() => _remaining = left);
      }
    });
  }

  Future<bool> _confirmReceive(TrustedDevice sender, bool pairing) async {
    if (!mounted) return false;
    final controller = VaultScope.read(context);
    final hasVault = controller.status != VaultStatus.needsSetup;
    final title = pairing
        ? 'Pair with ${sender.name}?'
        : 'Receive from ${sender.name}?';
    final base = pairing
        ? 'This remembers ${sender.name} as a trusted device. Only the '
              'already-encrypted vault is transferred; you still need its '
              'master password to open it.'
        : 'Accept the encrypted vault from ${sender.name}?';
    return confirmAction(
      context,
      title: title,
      message: hasVault
          ? '$base\n\nThis replaces the vault on this device. Export a backup '
                'first if you might need the current one.'
          : base,
      confirmLabel: pairing ? 'Pair and receive' : 'Receive vault',
      destructive: hasVault,
    );
  }

  Future<bool> _importReceived(String envelope, TrustedDevice sender) async {
    if (!mounted) return false;
    final controller = VaultScope.read(context);
    final imported = await controller.importEnvelope(envelope);
    if (!mounted) return imported;
    if (imported) {
      _countdown?.cancel();
      _countdown = null;
      setState(() {
        _pairedWith = sender.name;
        _pairedBySending = false;
        _offer = null;
        _receiveError = null;
      });
      // Let the HTTP response finish before closing the listener.
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 400), () async {
          await _receiver.stop();
          unawaited(controller.loadTrustedDevices(force: true));
        }),
      );
    } else {
      setState(() {
        _receiveError =
            controller.error ?? 'Could not import the received vault.';
      });
    }
    return imported;
  }

  Future<void> _scanAndPair() async {
    final controller = VaultScope.read(context);
    if (controller.status == VaultStatus.needsSetup) {
      setState(() {
        _pairError = 'Create or receive a vault on this device before pairing.';
      });
      return;
    }

    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const RawQrScannerScreen(
          title: 'Scan the computer QR code',
          hint: 'Point the camera at the trusted-device code on the computer.',
        ),
      ),
    );
    if (!mounted || scanned == null) return;

    final link = TrustPairingLink.tryParse(scanned);
    if (link == null) {
      setState(() {
        _pairError =
            'That is not a SecureID trusted-device code. On the computer open '
            'Settings → Trusted devices → Pair a new device and try again.';
      });
      return;
    }
    if (DateTime.now().isAfter(link.expiresAt)) {
      setState(() {
        _pairError =
            'That pairing code expired. Show a new code on the computer.';
      });
      return;
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pair with ${link.deviceName}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Check that this code matches the one on the computer screen.',
            ),
            const SizedBox(height: 16),
            Text(
              link.displayCode,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                letterSpacing: 8,
                fontWeight: FontWeight.w700,
                color: kMint,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pair and send'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    final identity = await controller.ensureDeviceIdentity();
    final envelope = await controller.readEncryptedEnvelope();
    if (!mounted) return;
    if (identity == null) {
      setState(() => _pairError = 'This build cannot identify this device.');
      return;
    }
    if (envelope == null || envelope.trim().isEmpty) {
      setState(() => _pairError = 'There is no vault on this device to send.');
      return;
    }

    setState(() {
      _pairing = true;
      _pairError = null;
      _pairedWith = null;
      _pairedBySending = false;
    });
    try {
      final device = await _sender.pairAndPush(
        link: link,
        senderId: identity.id,
        senderName: identity.name,
        senderPlatform: identity.platform,
        envelope: envelope,
      );
      await controller.rememberTrustedDevice(device);
      if (!mounted) return;
      setState(() {
        _pairing = false;
        _pairedWith = device.name;
        _pairedBySending = true;
      });
    } on TrustedTransferException catch (exception) {
      if (!mounted) return;
      setState(() {
        _pairing = false;
        _pairError = exception.message;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _pairing = false;
        _pairError = 'Could not pair: $exception';
      });
    }
  }

  Future<void> _pairAnother() async {
    setState(() {
      _pairedWith = null;
      _pairedBySending = false;
      _pairError = null;
      _receiveError = null;
    });
    if (_receiverMode) {
      await _startReceiver();
    }
  }

  Future<void> _useReceiver() async {
    setState(() {
      _showReceiver = true;
      _pairError = null;
    });
    await _startReceiver();
  }

  Future<void> _useScanner() async {
    await _receiver.stop();
    _countdown?.cancel();
    _countdown = null;
    if (!mounted) return;
    setState(() {
      _showReceiver = false;
      _offer = null;
      _receiveError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = VaultScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final title = widget.receiveOnly ? 'Receive updates' : 'Pair a new Device';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: GradientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_pairedWith != null)
                      ..._buildSuccess(context)
                    else if (!controller.trustedDeviceAvailable)
                      TrustedMessageCard(
                        icon: Icons.lock_outline_rounded,
                        color: kAccent,
                        message:
                            'Trusted devices are not available in this build.',
                      )
                    else if (_receiverMode)
                      ..._buildReceiver(context, controller)
                    else
                      ..._buildScanner(context),
                    const SizedBox(height: 22),
                    TrustedHintCard(
                      icon: Icons.shield_outlined,
                      title: 'What is stored',
                      body:
                          'Only the trust key is saved, protected by '
                          '${controller.trustedSealLabel}. Vault contents and '
                          'the master password never leave the encrypted '
                          'envelope.',
                    ),
                    if (scheme.brightness == Brightness.dark)
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSuccess(BuildContext context) {
    final name = _pairedWith!;
    return [
      TrustedMessageCard(
        icon: Icons.check_circle_rounded,
        color: kMint,
        message: _pairedBySending
            ? 'Paired with $name. The encrypted vault was sent to it.'
            : 'Paired with $name. Unlock the received vault with its master '
                  'password.',
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _pairAnother,
              icon: const Icon(Icons.add_link_rounded),
              label: const Text('Pair another device'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildReceiver(
    BuildContext context,
    VaultController controller,
  ) {
    return [
      TrustedSectionHeader(
        title: widget.receiveOnly
            ? 'Waiting for a linked device'
            : 'Show this code to the other device',
        subtitle: widget.receiveOnly
            ? 'On the other device open Trusted devices, tap Send, and choose '
                  'this device.'
            : 'Scan it from the phone or other device you want to pair. '
                  'Existing trusted devices are kept.',
      ),
      const SizedBox(height: 14),
      if (_receiveError != null) ...[
        TrustedMessageCard(
          icon: Icons.wifi_off_rounded,
          color: kDanger,
          message: _receiveError!,
        ),
        const SizedBox(height: 12),
      ],
      if (_startingReceiver)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_offer != null)
        TrustedPairingCard(
          offer: _offer!,
          remaining: _remaining,
          onNewCode: _startReceiver,
          statusLabel: widget.receiveOnly
              ? 'Waiting for a linked device…'
              : 'Waiting for a device…',
        )
      else
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _startReceiver,
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('Show pairing code'),
            ),
          ],
        ),
      if (_isPhone && !widget.receiveOnly) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pairing ? null : _useScanner,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Scan a computer code instead'),
        ),
      ],
    ];
  }

  List<Widget> _buildScanner(BuildContext context) {
    return [
      const TrustedSectionHeader(
        title: 'Pair with a computer',
        subtitle:
            'On the computer open Settings → Trusted devices → Pair a new '
            'device, then scan the code it shows.',
      ),
      const SizedBox(height: 16),
      if (_pairError != null) ...[
        TrustedMessageCard(
          icon: Icons.error_outline_rounded,
          color: kDanger,
          message: _pairError!,
        ),
        const SizedBox(height: 12),
      ],
      FilledButton.icon(
        onPressed: _pairing ? null : _scanAndPair,
        icon: _pairing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.qr_code_scanner_rounded),
        label: Text(_pairing ? 'Pairing…' : 'Scan the computer code'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _pairing ? null : _useReceiver,
        icon: const Icon(Icons.qr_code_2_rounded),
        label: const Text('Show a code instead'),
      ),
      const SizedBox(height: 10),
      Text(
        'Pairing sends this device\'s encrypted vault to the computer so both '
        'devices share the same vault. Export a backup first if you might need '
        'the current one on the computer.',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12.5,
          height: 1.45,
        ),
      ),
    ];
  }
}
