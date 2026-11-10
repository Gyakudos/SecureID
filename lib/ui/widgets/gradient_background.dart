import 'package:flutter/material.dart';

import '../theme.dart';

class GradientBackground extends StatelessWidget {
  const GradientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (isHighContrast(context)) {
      return ColoredBox(color: kHcBg, child: child);
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF070910), Color(0xFF0B1022), Color(0xFF070910)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -180,
            left: -140,
            child: _Glow(color: kAccent.withValues(alpha: 0.16), size: 440),
          ),
          Positioned(
            bottom: -200,
            right: -160,
            child: _Glow(color: kMint.withValues(alpha: 0.08), size: 480),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
