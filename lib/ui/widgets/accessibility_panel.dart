import 'package:flutter/material.dart';

import '../../models/accessibility_settings.dart';
import '../../state/vault_scope.dart';
import '../../util/speech_text.dart';

/// Opens the vision-accessibility controls as a bottom sheet.
Future<void> showAccessibilitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => const _AccessibilitySheet(),
  );
}

class _AccessibilitySheet extends StatelessWidget {
  const _AccessibilitySheet();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
          child: AccessibilityPanel(onClose: () => Navigator.of(context).pop()),
        ),
      ),
    );
  }
}

/// Controls for larger text, high contrast, and spoken accounts.
class AccessibilityPanel extends StatelessWidget {
  const AccessibilityPanel({super.key, this.onClose});

  final VoidCallback? onClose;

  static const _presets = <(double, String)>[
    (AccessibilitySettings.normalScale, '100%'),
    (AccessibilitySettings.largeScale, '130%'),
    (AccessibilitySettings.extraLargeScale, '160%'),
    (AccessibilitySettings.hugeScale, '200%'),
  ];

  Future<void> _apply(
    BuildContext context,
    AccessibilitySettings Function(AccessibilitySettings current) mutate,
  ) {
    final controller = VaultScope.read(context);
    return controller.updateAccessibility(mutate(controller.accessibility));
  }

  @override
  Widget build(BuildContext context) {
    final controller = VaultScope.of(context);
    final accessibility = controller.accessibility;
    final scheme = Theme.of(context).colorScheme;
    final speech = controller.speechAvailable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.accessibility_new_rounded,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vision & reading',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    accessibility.summary,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (onClose != null)
              IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'Make SecureID easier to see and hear. These settings stay on this '
          'device and apply before the vault is unlocked.',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        _Block(
          icon: Icons.text_fields_rounded,
          title: 'Text size',
          subtitle: 'Everything in the app grows, including this panel.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (scale, label) in _presets)
                ChoiceChip(
                  label: Text(label),
                  selected: (accessibility.textScale - scale).abs() < 0.01,
                  onSelected: (_) => _apply(
                    context,
                    (current) => current.copyWith(textScale: scale),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Block(
          icon: Icons.record_voice_over_rounded,
          title: 'Read accounts aloud',
          subtitle: speech
              ? 'Speak account names and summaries when you open them. '
                    'Passwords are never read in the summary.'
              : 'Text-to-speech is not available on this device.',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable spoken accounts'),
            value: accessibility.readAloud,
            onChanged: speech
                ? (value) => _apply(
                    context,
                    (current) => current.copyWith(readAloud: value),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 12),
        _Block(
          icon: Icons.contrast_rounded,
          title: 'High contrast',
          subtitle: 'Pure black background with brighter text and borders.',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use high-contrast colours'),
            value: accessibility.highContrast,
            onChanged: (value) => _apply(
              context,
              (current) => current.copyWith(highContrast: value),
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (speech)
          FilledButton.icon(
            onPressed: controller.isSpeaking
                ? controller.stopSpeaking
                : () => controller.speak(
                    controller.isUnlocked
                        ? itemsSpeech(controller.items)
                        : 'SecureID is ready. Turn on read accounts aloud to '
                              'hear your accounts after unlocking.',
                  ),
            icon: Icon(
              controller.isSpeaking
                  ? Icons.stop_rounded
                  : Icons.volume_up_rounded,
            ),
            label: Text(
              controller.isSpeaking
                  ? 'Stop reading'
                  : controller.isUnlocked
                  ? 'Read my accounts aloud'
                  : 'Test the voice',
            ),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () =>
              _apply(context, (_) => const AccessibilitySettings()),
          child: const Text('Reset to standard settings'),
        ),
        const SizedBox(height: 6),
        Text(
          'Tip: your phone and Windows also have system text-size and '
          'screen-reader settings. SecureID adds to those rather than '
          'replacing them.',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer.withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 19, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
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
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}
