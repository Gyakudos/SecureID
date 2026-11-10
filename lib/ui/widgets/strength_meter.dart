import 'package:flutter/material.dart';

import '../../security/password_strength.dart';
import '../theme.dart';

class StrengthMeter extends StatelessWidget {
  const StrengthMeter({
    super.key,
    required this.password,
    this.showBits = true,
  });

  final String password;
  final bool showBits;

  @override
  Widget build(BuildContext context) {
    final strength = estimatePasswordStrength(password);
    const colors = [
      kDanger,
      Color(0xFFFFA94D),
      Color(0xFFFFD166),
      kMint,
      Color(0xFF7CFFB2),
    ];
    final color = colors[strength.score];
    final value = password.isEmpty ? 0.0 : (strength.score + 1) / 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              strength.label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        if (showBits) ...[
          const SizedBox(height: 6),
          Text(
            '${strength.bits.round()} bits of estimated entropy',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}
