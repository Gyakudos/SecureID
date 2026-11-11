import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A 3x3 pattern lock. Drag across dots to draw a pattern.
///
/// Dot indexes run left-to-right, top-to-bottom (0-8). The pad reports a
/// complete pattern once the finger is lifted and at least four dots were
/// crossed.
class PatternPad extends StatefulWidget {
  const PatternPad({
    super.key,
    this.size = 280,
    this.minDots = 4,
    this.enabled = true,
    required this.onCompleted,
  });

  final double size;
  final int minDots;
  final bool enabled;
  final ValueChanged<List<int>> onCompleted;

  @override
  State<PatternPad> createState() => _PatternPadState();
}

class _PatternPadState extends State<PatternPad> {
  final List<int> _dots = [];
  bool _dragging = false;

  List<Offset> _centers() {
    final padding = widget.size * 0.16;
    final span = widget.size - padding * 2;
    final step = span / 2;
    return [
      for (var row = 0; row < 3; row++)
        for (var column = 0; column < 3; column++)
          Offset(padding + column * step, padding + row * step),
    ];
  }

  int? _dotAt(Offset position) {
    final radius = widget.size * 0.1;
    final centers = _centers();
    for (var i = 0; i < centers.length; i++) {
      if ((centers[i] - position).distance <= radius) return i;
    }
    return null;
  }

  void _start(Offset position) {
    if (!widget.enabled) return;
    final dot = _dotAt(position);
    setState(() {
      _dots
        ..clear()
        ..addAll(dot == null ? const <int>[] : [dot]);
      _dragging = dot != null;
    });
  }

  void _move(Offset position) {
    if (!_dragging) return;
    final dot = _dotAt(position);
    if (dot == null || _dots.contains(dot)) return;
    setState(() => _dots.add(dot));
  }

  void _end() {
    if (!_dragging) return;
    final result = List<int>.of(_dots);
    setState(() {
      _dragging = false;
      _dots.clear();
    });
    if (result.length >= widget.minDots) widget.onCompleted(result);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final centers = _centers();
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => _start(details.localPosition),
        onPanUpdate: (details) => _move(details.localPosition),
        onPanEnd: (_) => _end(),
        onPanCancel: _end,
        child: CustomPaint(
          painter: _PatternPainter(
            dots: List<int>.of(_dots),
            centers: centers,
            dotRadius: math.max(6, widget.size * 0.026),
            lineColor: scheme.primary,
            idleColor: scheme.outline,
            activeColor: scheme.primary,
            surfaceColor: scheme.surfaceContainerHigh,
          ),
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.dots,
    required this.centers,
    required this.dotRadius,
    required this.lineColor,
    required this.idleColor,
    required this.activeColor,
    required this.surfaceColor,
  });

  final List<int> dots;
  final List<Offset> centers;
  final double dotRadius;
  final Color lineColor;
  final Color idleColor;
  final Color activeColor;
  final Color surfaceColor;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = math.max(3, size.width * 0.014)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (var i = 0; i + 1 < dots.length; i++) {
      canvas.drawLine(centers[dots[i]], centers[dots[i + 1]], line);
    }

    final fill = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < centers.length; i++) {
      final active = dots.contains(i);
      fill.color = active ? activeColor : surfaceColor;
      canvas.drawCircle(centers[i], dotRadius + 4, fill);
      fill.color = active ? activeColor : idleColor;
      canvas.drawCircle(centers[i], active ? dotRadius : dotRadius * 0.6, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) {
    return !_sameDots(oldDelegate.dots, dots) ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.activeColor != activeColor;
  }

  static bool _sameDots(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
