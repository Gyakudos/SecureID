import 'package:flutter/material.dart';

import '../../models/vault_settings.dart';
import '../../security/password_generator.dart';
import '../theme.dart';
import 'strength_meter.dart';

/// Shows the password generator and returns the chosen password, or null.
Future<String?> showPasswordGeneratorDialog(
  BuildContext context, {
  VaultSettings? settings,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PasswordGeneratorDialog(settings: settings),
  );
}

class _PasswordGeneratorDialog extends StatefulWidget {
  const _PasswordGeneratorDialog({this.settings});

  final VaultSettings? settings;

  @override
  State<_PasswordGeneratorDialog> createState() =>
      _PasswordGeneratorDialogState();
}

class _PasswordGeneratorDialogState extends State<_PasswordGeneratorDialog> {
  late int _length;
  late bool _upper;
  late bool _lower;
  late bool _digits;
  late bool _symbols;
  late bool _excludeAmbiguous;
  late String _password;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = widget.settings;
    _length = settings?.generatorLength ?? 20;
    _upper = settings?.generatorUpper ?? true;
    _lower = settings?.generatorLower ?? true;
    _digits = settings?.generatorDigits ?? true;
    _symbols = settings?.generatorSymbols ?? true;
    _excludeAmbiguous = settings?.generatorExcludeAmbiguous ?? false;
    _generate();
  }

  void _generate() {
    try {
      _password = PasswordGenerator.generate(
        length: _length,
        upper: _upper,
        lower: _lower,
        useDigits: _digits,
        useSymbols: _symbols,
        excludeAmbiguous: _excludeAmbiguous,
      );
      _error = null;
    } on ArgumentError catch (exception) {
      _password = '';
      _error = exception.message?.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Password generator'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: SelectableText(
                  _password.isEmpty ? '—' : _password,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
                    height: 1.5,
                    letterSpacing: 0.6,
                    color: _password.isEmpty ? scheme.error : scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error, fontSize: 12),
                )
              else
                StrengthMeter(password: _password, showBits: true),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    'Length',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    '$_length',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              Slider(
                value: _length.toDouble(),
                min: 8,
                max: 64,
                divisions: 56,
                label: '$_length',
                onChanged: (value) => setState(() {
                  _length = value.round();
                  _generate();
                }),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _toggle('A-Z', _upper, (value) {
                    setState(() {
                      _upper = value;
                      _generate();
                    });
                  }),
                  _toggle('a-z', _lower, (value) {
                    setState(() {
                      _lower = value;
                      _generate();
                    });
                  }),
                  _toggle('0-9', _digits, (value) {
                    setState(() {
                      _digits = value;
                      _generate();
                    });
                  }),
                  _toggle('!@#', _symbols, (value) {
                    setState(() {
                      _symbols = value;
                      _generate();
                    });
                  }),
                  _toggle('No 0/O/1/l', _excludeAmbiguous, (value) {
                    setState(() {
                      _excludeAmbiguous = value;
                      _generate();
                    });
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => setState(_generate),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Regenerate'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _password.isEmpty
              ? null
              : () => Navigator.pop(context, _password),
          child: const Text('Use password'),
        ),
      ],
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
      checkmarkColor: kMint,
    );
  }
}
