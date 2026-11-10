import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/lan_pairing.dart';
import '../../state/vault_controller.dart';
import '../../state/vault_scope.dart';
import '../scanner/raw_qr_scanner_screen.dart';
import '../theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/gradient_background.dart';

/// Moves the already-encrypted vault between this device and a phone.
///
/// Both layers are offered:
/// - **Send**: this device serves the encrypted envelope over the local
///   network and shows a one-time QR code. Works with no account and no
///   internet connection.
/// - **Receive**: scan or paste a `secureid://pair?...` link from another
///   device and replace this device's vault with the received one.
///
/// The vault is never decrypted during transfer. The receiving device still
/// needs the master password to open it.
class LinkPhoneScreen extends StatefulWidget {
  const LinkPhoneScreen({super.key, this.initialTab = 0});

  /// 0 sends from this device, 1 receives from another device.
  final int initialTab;

  @override
  State<LinkPhoneScreen> createState() => _LinkPhoneScreenState();
}

class _LinkPhoneScreenState extends State<LinkPhoneScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 1),
  );

  final TextEditingController _linkText = TextEditingController();

  LanPairingServer? _server;
  LanPairingOffer? _offer;
  bool _starting = false;
  bool _sent = false;
  String? _sendError;
  Timer? _countdown;
  Duration _remaining = Duration.zero;

  bool _receiving = false;
  String? _receiveError;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _tabs.index == 0) _startSending();
    });
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _countdown?.cancel();
    _linkText.dispose();
    unawaited(_server?.stop());
    _server = null;
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == 0) {
      if (_server == null && !_starting) _startSending();
    } else {
      unawaited(_server?.stop());
      _server = null;
      _countdown?.cancel();
      _countdown = null;
      if (mounted) {
        setState(() {
          _offer = null;
          _sent = false;
          _sendError = null;
          _remaining = Duration.zero;
        });
      }
    }
  }

  Future<void> _startSending() async {
    final controller = VaultScope.read(context);
    if (controller.status == VaultStatus.needsSetup) {
      setState(() => _sendError = 'Create a vault on this device first.');
      return;
    }

    final identity = await controller.ensureDeviceIdentity();
    if (!mounted) return;
    setState(() {
      _starting = true;
      _sendError = null;
      _sent = false;
      _offer = null;
    });

    await _server?.stop();
    final server = LanPairingServer();
    try {
      final offer = await server.start(
        readEnvelope: controller.readEncryptedEnvelope,
        deviceName: identity?.name ?? 'SecureID device',
        onSent: () {
          if (!mounted) return;
          setState(() => _sent = true);
        },
      );
      if (!mounted) {
        await server.stop();
        return;
      }
      _server = server;
      setState(() {
        _offer = offer;
        _starting = false;
        _remaining = offer.expiresAt.difference(DateTime.now());
      });
      _countdown?.cancel();
      _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
        final current = _offer;
        if (current == null) return;
        final left = current.expiresAt.difference(DateTime.now());
        if (!mounted) return;
        if (left.isNegative || left == Duration.zero) {
          _countdown?.cancel();
          _countdown = null;
          setState(() {
            _remaining = Duration.zero;
            _offer = null;
          });
          unawaited(_server?.stop());
          _server = null;
        } else {
          setState(() => _remaining = left);
        }
      });
    } on PairingException catch (exception) {
      await server.stop();
      if (!mounted) return;
      setState(() {
        _starting = false;
        _sendError = exception.message;
      });
    } catch (exception) {
      await server.stop();
      if (!mounted) return;
      setState(() {
        _starting = false;
        _sendError = 'Could not start the link: $exception';
      });
    }
  }

  Future<void> _copyLink() async {
    final link = _offer?.link.encode();
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Pairing link copied.')));
  }

  Future<void> _scan() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const RawQrScannerScreen(
          title: 'Scan the pairing QR code',
          hint: 'Point the camera at the QR code shown on the other device.',
        ),
      ),
    );
    if (!mounted || scanned == null) return;
    setState(() {
      _linkText.text = scanned;
      _receiveError = null;
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted || text == null || text.trim().isEmpty) return;
    setState(() {
      _linkText.text = text.trim();
      _receiveError = null;
    });
  }

  Future<void> _receive() async {
    final controller = VaultScope.read(context);
    final link = PairingLink.tryParse(_linkText.text);
    if (link == null) {
      setState(() {
        _receiveError =
            'That does not look like a SecureID pairing link. Paste the whole '
            'secureid://pair?... code.';
      });
      return;
    }

    if (controller.status != VaultStatus.needsSetup) {
      final confirmed = await confirmAction(
        context,
        title: 'Replace this vault?',
        message:
            'This device already has a vault. Receiving the link will replace '
            'it with the vault from the other device. You will need that '
            'vault\'s master password to unlock it.',
        confirmLabel: 'Receive and replace',
        destructive: true,
      );
      if (!confirmed) return;
    }

    setState(() {
      _receiving = true;
      _receiveError = null;
    });
    try {
      final envelope = await LanPairingClient().fetchEnvelope(link);
      final imported = await controller.importEnvelope(envelope);
      if (!mounted) return;
      if (!imported) {
        setState(() {
          _receiving = false;
          _receiveError =
              controller.error ?? 'Could not import the received vault.';
        });
        return;
      }
      setState(() => _receiving = false);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Vault received'),
          content: const Text(
            'The encrypted vault was copied to this device. Unlock it with '
            'that vault\'s master password.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Unlock now'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on PairingException catch (exception) {
      if (!mounted) return;
      setState(() {
        _receiving = false;
        _receiveError = exception.message;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _receiving = false;
        _receiveError = 'Could not receive the vault: $exception';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Link a phone'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Send from this device'),
            Tab(text: 'Receive from a device'),
          ],
        ),
      ),
      body: GradientBackground(
        child: SafeArea(
          child: TabBarView(
            controller: _tabs,
            children: [_buildSend(context), _buildReceive(context)],
          ),
        ),
      ),
    );
  }

  Widget _buildSend(BuildContext context) {
    final controller = VaultScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final offer = _offer;
    final ready = controller.status != VaultStatus.needsSetup;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Show this code on the phone you want to link',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Both devices must be on the same Wi-Fi or local network. '
                'Only the encrypted vault is sent, so the transfer is safe on '
                'a trusted network.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              if (!ready)
                _MessageCard(
                  icon: Icons.lock_outline_rounded,
                  color: kAccent,
                  message:
                      'Create a vault on this device before linking a '
                      'phone.',
                )
              else if (_starting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (offer != null)
                _QrCard(
                  offer: offer,
                  sent: _sent,
                  remaining: _remaining,
                  onCopy: _copyLink,
                  onNewCode: _startSending,
                )
              else
                Column(
                  children: [
                    if (_sendError != null) ...[
                      _MessageCard(
                        icon: Icons.wifi_off_rounded,
                        color: kDanger,
                        message: _sendError!,
                      ),
                      const SizedBox(height: 14),
                    ],
                    FilledButton.icon(
                      onPressed: _startSending,
                      icon: const Icon(Icons.qr_code_2_rounded),
                      label: const Text('Show a new code'),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              _HintCard(
                icon: Icons.shield_outlined,
                title: 'Zero-knowledge transfer',
                body:
                    'The receiving device gets the same encrypted envelope '
                    'that is stored on this device. It still needs the master '
                    'password to open it, and the link works once.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceive(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = VaultScope.of(context);
    final hasVault = controller.status != VaultStatus.needsSetup;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Scan or paste the code from the other device',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'On the other device open Settings → Link a phone → Send, '
                'then scan the QR code here.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _linkText,
                minLines: 2,
                maxLines: 5,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Pairing link',
                  hintText: 'secureid://pair?u=...&t=...',
                  prefixIcon: Icon(Icons.link_rounded),
                ),
                onChanged: (_) {
                  if (_receiveError != null) {
                    setState(() => _receiveError = null);
                  }
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (Platform.isAndroid) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _receiving ? null : _scan,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: const Text('Scan QR'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _receiving ? null : _paste,
                      icon: const Icon(Icons.content_paste_rounded),
                      label: const Text('Paste'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_receiveError != null) ...[
                _MessageCard(
                  icon: Icons.error_outline_rounded,
                  color: kDanger,
                  message: _receiveError!,
                ),
                const SizedBox(height: 14),
              ],
              FilledButton.icon(
                onPressed: _receiving ? null : _receive,
                icon: _receiving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(_receiving ? 'Receiving…' : 'Receive vault'),
              ),
              if (hasVault) ...[
                const SizedBox(height: 20),
                _MessageCard(
                  icon: Icons.warning_amber_rounded,
                  color: kAccent,
                  message:
                      'This device already has a vault. Receiving another '
                      'one replaces it. Export a backup first if you might need '
                      'the current vault.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({
    required this.offer,
    required this.sent,
    required this.remaining,
    required this.onCopy,
    required this.onNewCode,
  });

  final LanPairingOffer offer;
  final bool sent;
  final Duration remaining;
  final VoidCallback onCopy;
  final VoidCallback onNewCode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expired = remaining == Duration.zero && !sent;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: QrImageView(
                  data: offer.link.encode(),
                  version: QrVersions.auto,
                  size: 232,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                offer.link.deviceName.isEmpty
                    ? 'SecureID vault'
                    : offer.link.deviceName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${offer.address} · expires in $minutes:$seconds',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _StatusPill(sent: sent, expired: expired),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy link'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: onNewCode,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('New code'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.sent, required this.expired});

  final bool sent;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final color = sent ? kMint : (expired ? kDanger : kAccent);
    final label = sent
        ? 'Vault sent — this code is now used'
        : (expired ? 'This code expired' : 'Waiting for the phone…');
    final icon = sent
        ? Icons.check_circle_rounded
        : (expired ? Icons.timer_off_rounded : Icons.wifi_tethering_rounded);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label, style: TextStyle(color: color, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: kMint, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
