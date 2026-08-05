import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// A tiny, axis-free trend line used inside account cards.
///
/// Coloured by the caller (defaulting to a growth / shrinkage cue) with a
/// soft gradient fill so a card's balance history reads at a glance.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.height = 36,
    this.color,
  });

  /// Balance points in minor units, oldest first.
  final List<int> values;

  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ??
        (values.isEmpty || values.last >= values.first
            ? AppColors.income
            : AppColors.expense);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SparklinePainter(values, resolved)),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color);

  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    var min = values.first;
    var max = values.first;
    for (final value in values) {
      if (value < min) min = value;
      if (value > max) max = value;
    }
    if (max == min) {
      // Flat series (e.g. a brand-new account): draw a centred line.
      final midY = size.height / 2;
      canvas.drawPath(
        Path()
          ..moveTo(0, midY)
          ..lineTo(size.width, midY),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
      return;
    }
    final spread = (max - min).toDouble();

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y =
          size.height - 2 - (values[i] - min) / spread * (size.height - 4);
      points.add(Offset(x, y));
    }

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }

    final fill = Path.from(line)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fill, fillPaint);

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      !listEquals(oldDelegate.values, values) || oldDelegate.color != color;
}
