import 'package:flutter/material.dart';

import '../theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kAccent, Color(0xFF5B4BDB)],
        ),
        boxShadow: [
          BoxShadow(
            color: kAccent.withValues(alpha: 0.35),
            blurRadius: size * 0.45,
            offset: Offset(0, size * 0.16),
          ),
        ],
      ),
      child: Icon(Icons.shield_rounded, size: size * 0.56, color: Colors.white),
    );
  }
}
