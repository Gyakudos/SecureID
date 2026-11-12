import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  Offset? _lastPoint;

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
      _dots.clear();
      _dragging = dot != null;
      _lastPoint = position;
      if (dot != null) _dots.add(dot);
    });
    if (dot != null) _haptic();
  }

  void _move(Offset position) {
    if (!_dragging) return;
    final last = _lastPoint;
    _lastPoint = position;
    if (last == null) return;

    // A fast stroke can jump from one dot to the next without a pointer event
    // landing inside the dot. Walk the segment and collect every dot the
    // finger passed over.
    final distance = (position - last).distance;
    final step = math.max(2.0, widget.size * 0.02);
    final samples = math.max(1, (distance / step).ceil());
    var changed = false;
    for (var i = 1; i <= samples; i++) {
      final sample = Offset.lerp(last, position, i / samples);
      if (sample == null) continue;
      final dot = _dotAt(sample);
      if (dot != null && !_dots.contains(dot)) {
        _dots.add(dot);
        changed = true;
      }
    }
    if (!changed) return;
    setState(() {});
    _haptic();
  }

  void _end() {
    if (!_dragging) return;
    final result = List<int>.of(_dots);
    setState(() {
      _dragging = false;
      _dots.clear();
      _lastPoint = null;
    });
    if (result.length >= widget.minDots) widget.onCompleted(result);
  }

  void _haptic() {
    // Haptics are a nicety, not a requirement, so failures are ignored.
    try {
      HapticFeedback.selectionClick();
    } catch (_) {
      // Ignore platforms without haptic feedback.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final centers = _centers();
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          _EagerPanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<_EagerPanGestureRecognizer>(
                () => _EagerPanGestureRecognizer(),
                (recognizer) {
                  recognizer.onStart = (details) =>
                      _start(details.localPosition);
                  recognizer.onUpdate = (details) =>
                      _move(details.localPosition);
                  recognizer.onEnd = (_) => _end();
                  recognizer.onCancel = _end;
                },
              ),
        },
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

/// A pan recognizer that claims the pointer as soon as it goes down.
///
/// The pattern pad is often shown inside a [SingleChildScrollView]. A normal
/// pan recognizer competes with the scroll view's drag recognizer, and the
/// scroll view wins on vertical strokes, so the pattern never gets drawn.
/// Accepting eagerly keeps the stroke inside the pad.
class _EagerPanGestureRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
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
