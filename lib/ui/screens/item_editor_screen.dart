import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/passkey.dart';
import '../../models/totp.dart';
import '../../models/vault_item.dart';
import '../../security/totp.dart';
import '../../state/vault_scope.dart';
import '../scanner/qr_scanner_screen.dart';
import '../theme.dart';
import '../widgets/gradient_background.dart';
import '../widgets/password_generator_dialog.dart';
import '../widgets/totp_display.dart';

class ItemEditorScreen extends StatefulWidget {
  const ItemEditorScreen({super.key, required this.item});

  /// A mutable copy of the item being edited. New items are created with one
  /// of the `VaultItem.newX()` factories.
  final VaultItem item;

  @override
  State<ItemEditorScreen> createState() => _ItemEditorScreenState();
}

class _ItemEditorScreenState extends State<ItemEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _url;
  late final TextEditingController _notes;
  late final TextEditingController _tags;

  late final TextEditingController _rpId;
  late final TextEditingController _rpName;
  late final TextEditingController _pkAccount;
  late final TextEditingController _credentialId;
  late final TextEditingController _userHandle;
  late final TextEditingController _cose;
  late final TextEditingController _aaguid;
  late final TextEditingController _signCount;

  late final TextEditingController _totpIssuer;
  late final TextEditingController _totpAccount;
  late final TextEditingController _totpSecret;

  late bool _favorite;
  bool _obscurePassword = true;
  bool _obscureSecret = true;
  bool _discoverable = true;
  int _passkeyAlgorithm = -7;
  TotpAlgorithm _algorithm = TotpAlgorithm.sha1;
  int _digits = 6;
  int _period = 30;
  String? _error;

  VaultItemKind get _kind => widget.item.kind;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    final passkey = item.passkey;
    final totp = item.totp;

    _title = TextEditingController(text: item.title);
    _username = TextEditingController(text: item.username);
    _password = TextEditingController(text: item.password);
    _url = TextEditingController(text: item.url);
    _notes = TextEditingController(text: item.notes);
    _tags = TextEditingController(text: item.tags.join(', '));
    _favorite = item.favorite;

    _rpId = TextEditingController(text: passkey?.relyingPartyId ?? '');
    _rpName = TextEditingController(text: passkey?.relyingPartyName ?? '');
    _pkAccount = TextEditingController(text: passkey?.accountName ?? '');
    _credentialId = TextEditingController(text: passkey?.credentialId ?? '');
    _userHandle = TextEditingController(text: passkey?.userHandle ?? '');
    _cose = TextEditingController(text: passkey?.publicKeyCose ?? '');
    _aaguid = TextEditingController(text: passkey?.aaguid ?? '');
    _signCount = TextEditingController(
      text: (passkey?.signCount ?? 0).toString(),
    );
    _discoverable = passkey?.discoverable ?? true;
    _passkeyAlgorithm = passkey?.algorithm ?? -7;

    _totpIssuer = TextEditingController(text: totp?.issuer ?? '');
    _totpAccount = TextEditingController(text: totp?.accountName ?? '');
    _totpSecret = TextEditingController(text: totp?.secret ?? '');
    _algorithm = totp?.algorithm ?? TotpAlgorithm.sha1;
    _digits = totp?.digits ?? 6;
    _period = totp?.period ?? 30;
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _username,
      _password,
      _url,
      _notes,
      _tags,
      _rpId,
      _rpName,
      _pkAccount,
      _credentialId,
      _userHandle,
      _cose,
      _aaguid,
      _signCount,
      _totpIssuer,
      _totpAccount,
      _totpSecret,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  TotpData get _currentTotp => TotpData(
    issuer: _totpIssuer.text.trim(),
    accountName: _totpAccount.text.trim(),
    secret: _totpSecret.text.trim(),
    algorithm: _algorithm,
    digits: _digits,
    period: _period,
  );

  Future<void> _generatePassword() async {
    final controller = VaultScope.read(context);
    final generated = await showPasswordGeneratorDialog(
      context,
      settings: controller.settings,
    );
    if (generated == null) return;
    setState(() {
      _password.text = generated;
      _obscurePassword = false;
    });
  }

  Future<void> _scanQr() async {
    final data = await Navigator.of(context).push<TotpData>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (data == null || !mounted) return;
    _applyTotpData(data);
  }

  Future<void> _pasteLink() async {
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => const _PasteLinkDialog(),
    );
    if (raw == null || raw.trim().isEmpty || !mounted) return;
    try {
      final data = parseOtpAuthUri(raw);
      _applyTotpData(data);
    } on TotpException catch (exception) {
      setState(() => _error = exception.message);
    }
  }

  void _applyTotpData(TotpData data) {
    setState(() {
      _totpIssuer.text = data.issuer;
      _totpAccount.text = data.accountName;
      _totpSecret.text = data.secret;
      _algorithm = data.algorithm;
      _digits = data.digits;
      _period = data.period;
      _error = null;
      if (_title.text.trim().isEmpty) {
        _title.text = data.issuer.isNotEmpty
            ? data.issuer
            : (data.accountName.isNotEmpty
                  ? data.accountName
                  : 'Authenticator');
      }
    });
  }

  Future<void> _save() async {
    final controller = VaultScope.read(context);
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give this item a title.');
      return;
    }

    final item = widget.item;
    item.title = title;
    item.favorite = _favorite;
    item.tags = _tags.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: true);

    switch (_kind) {
      case VaultItemKind.login:
        item.username = _username.text.trim();
        item.password = _password.text;
        item.url = _url.text.trim();
        item.notes = _notes.text;
        final secret = _totpSecret.text.trim();
        if (secret.isEmpty) {
          item.totp = null;
        } else {
          try {
            final data = TotpData(
              issuer: _totpIssuer.text.trim(),
              accountName: _totpAccount.text.trim(),
              secret: normalizeTotpSecret(secret),
              algorithm: _algorithm,
              digits: _digits,
              period: _period,
            );
            // Verifies the secret and parameters before it is saved.
            generateTotp(data);
            item.totp = data;
          } on TotpException catch (exception) {
            setState(() => _error = exception.message);
            return;
          }
        }
      case VaultItemKind.passkey:
        final passkey = item.passkey ?? PasskeyData();
        passkey.relyingPartyId = _rpId.text.trim();
        passkey.relyingPartyName = _rpName.text.trim();
        passkey.accountName = _pkAccount.text.trim();
        passkey.credentialId = _credentialId.text.trim();
        passkey.userHandle = _userHandle.text.trim();
        passkey.publicKeyCose = _cose.text.trim();
        passkey.aaguid = _aaguid.text.trim();
        passkey.algorithm = _passkeyAlgorithm;
        passkey.signCount = int.tryParse(_signCount.text.trim()) ?? 0;
        passkey.discoverable = _discoverable;
        if (!passkey.isValid) {
          setState(() {
            _error =
                'A passkey needs a relying party ID, an account and a '
                'credential ID.';
          });
          return;
        }
        item.passkey = passkey;
      case VaultItemKind.totp:
        try {
          final secret = normalizeTotpSecret(_totpSecret.text);
          if (secret.isEmpty) {
            throw const TotpException('Enter the Base32 secret.');
          }
          final data = TotpData(
            issuer: _totpIssuer.text.trim(),
            accountName: _totpAccount.text.trim(),
            secret: secret,
            algorithm: _algorithm,
            digits: _digits,
            period: _period,
          );
          // Verifies the secret and parameters before it is saved.
          generateTotp(data);
          item.totp = data;
        } on TotpException catch (exception) {
          setState(() => _error = exception.message);
          return;
        }
    }

    await controller.upsertItem(item);
    if (!mounted) return;
    if (controller.error != null) {
      setState(() => _error = controller.error);
      return;
    }
    Navigator.of(context).pop(true);
  }

  String get _heading => switch (_kind) {
    VaultItemKind.login => 'login',
    VaultItemKind.passkey => 'passkey',
    VaultItemKind.totp => 'authenticator',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNew = widget.item.title.isEmpty;
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 20, 6),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            isNew ? 'New $_heading' : 'Edit $_heading',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Save'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null) ...[
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
                                      _error!,
                                      style: TextStyle(
                                        color: scheme.error,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          _Section(
                            title: 'Details',
                            child: Column(
                              children: [
                                TextField(
                                  controller: _title,
                                  autofocus: isNew,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: const InputDecoration(
                                    labelText: 'Title',
                                    hintText: 'e.g. GitHub',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _tags,
                                  decoration: const InputDecoration(
                                    labelText: 'Tags',
                                    hintText: 'work, personal',
                                    prefixIcon: Icon(Icons.sell_outlined),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _favorite,
                                  onChanged: (value) =>
                                      setState(() => _favorite = value),
                                  title: const Text('Favorite'),
                                  subtitle: const Text(
                                    'Pin this item to the top of the vault',
                                  ),
                                  secondary: Icon(
                                    _favorite
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    color: _favorite ? kMint : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_kind == VaultItemKind.login) ...[
                            _buildLoginFields(),
                            const SizedBox(height: 14),
                            _buildTotpFields(
                              title: 'Two-factor authentication',
                              subtitle:
                                  'Optional. Add the authenticator secret '
                                  'to see live 2FA codes next to this login.',
                            ),
                          ] else if (_kind == VaultItemKind.passkey)
                            _buildPasskeyFields()
                          else
                            _buildTotpFields(),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _save,
                            icon: const Icon(Icons.lock_rounded, size: 18),
                            label: const Text('Save to vault'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginFields() {
    return _Section(
      title: 'Login',
      child: Column(
        children: [
          TextField(
            controller: _username,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Username or email',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscurePassword,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.password_rounded),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Generate password',
                    onPressed: _generatePassword,
                    icon: const Icon(Icons.auto_awesome_rounded),
                  ),
                  IconButton(
                    tooltip: _obscurePassword ? 'Show' : 'Hide',
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Website',
              hintText: 'https://example.com',
              prefixIcon: Icon(Icons.link_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasskeyFields() {
    return _Section(
      title: 'Passkey metadata',
      child: Column(
        children: [
          TextField(
            controller: _rpId,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Relying party ID',
              hintText: 'github.com',
              prefixIcon: Icon(Icons.language_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _rpName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Relying party name',
              hintText: 'GitHub',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pkAccount,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Account',
              hintText: 'alice@example.com',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _credentialId,
            autocorrect: false,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Credential ID (Base64url)',
              prefixIcon: Icon(Icons.fingerprint_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _userHandle,
            autocorrect: false,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'User handle (Base64url)',
              prefixIcon: Icon(Icons.tag_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cose,
            autocorrect: false,
            minLines: 2,
            maxLines: 5,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'COSE public key (Base64)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey('passkey-algorithm-$_passkeyAlgorithm'),
            initialValue: _passkeyAlgorithm,
            decoration: const InputDecoration(
              labelText: 'Algorithm',
              prefixIcon: Icon(Icons.functions_rounded),
            ),
            items: const [
              DropdownMenuItem(value: -7, child: Text('ES256 · P-256')),
              DropdownMenuItem(value: -257, child: Text('RS256 · RSA')),
              DropdownMenuItem(value: -8, child: Text('EdDSA · Ed25519')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _passkeyAlgorithm = value);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _signCount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Signature counter',
                    prefixIcon: Icon(Icons.numbers_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _aaguid,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'AAGUID',
                    hintText: 'Optional',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _discoverable,
            onChanged: (value) => setState(() => _discoverable = value),
            title: const Text('Discoverable credential'),
            subtitle: const Text('Resident key stored on the authenticator'),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kMint.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kMint.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: kMint),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'SecureID stores passkey metadata for backup and auditing. '
                    'The private key never leaves the authenticator that '
                    'created it, so this record cannot sign in on its own.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotpFields({String title = 'Authenticator', String? subtitle}) {
    final scheme = Theme.of(context).colorScheme;
    final canScan = Platform.isAndroid;
    final hasSecret = _totpSecret.text.trim().isNotEmpty;
    return _Section(
      title: title,
      child: Column(
        children: [
          if (subtitle != null) ...[
            Text(
              subtitle,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _totpIssuer,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Issuer',
                    hintText: 'GitHub',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _totpAccount,
                  autocorrect: false,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Account',
                    hintText: 'alice@example.com',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _totpSecret,
            obscureText: _obscureSecret,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: 'Base32 secret',
              hintText: 'JBSWY3DPEHPK3PXP',
              prefixIcon: const Icon(Icons.key_rounded),
              suffixIcon: IconButton(
                tooltip: _obscureSecret ? 'Show secret' : 'Hide secret',
                onPressed: () =>
                    setState(() => _obscureSecret = !_obscureSecret),
                icon: Icon(
                  _obscureSecret
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canScan ? _scanQr : null,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: const Text('Scan QR'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pasteLink,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('Paste link'),
                ),
              ),
            ],
          ),
          if (!canScan)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'QR scanning is available on Android. Paste an otpauth:// '
                'link or type the secret on desktop.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TotpAlgorithm>(
                  key: ValueKey('totp-algorithm-$_algorithm'),
                  initialValue: _algorithm,
                  decoration: const InputDecoration(labelText: 'Algorithm'),
                  items: TotpAlgorithm.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _algorithm = value);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('totp-digits-$_digits'),
                  initialValue: _digits,
                  decoration: const InputDecoration(labelText: 'Digits'),
                  items: const [
                    DropdownMenuItem(value: 6, child: Text('6')),
                    DropdownMenuItem(value: 7, child: Text('7')),
                    DropdownMenuItem(value: 8, child: Text('8')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _digits = value);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('totp-period-$_period'),
                  initialValue: _period,
                  decoration: const InputDecoration(labelText: 'Period'),
                  items: const [
                    DropdownMenuItem(value: 30, child: Text('30s')),
                    DropdownMenuItem(value: 60, child: Text('60s')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _period = value);
                  },
                ),
              ),
            ],
          ),
          if (hasSecret) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Live preview',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TotpCodeView(data: _currentTotp),
                      ],
                    ),
                  ),
                  Icon(Icons.shield_moon_rounded, color: kMint),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _PasteLinkDialog extends StatefulWidget {
  const _PasteLinkDialog();

  @override
  State<_PasteLinkDialog> createState() => _PasteLinkDialogState();
}

class _PasteLinkDialogState extends State<_PasteLinkDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paste otpauth:// link'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        autocorrect: false,
        decoration: const InputDecoration(
          hintText: 'otpauth://totp/GitHub:alice?secret=…&issuer=GitHub',
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Import'),
        ),
      ],
    );
  }
}
