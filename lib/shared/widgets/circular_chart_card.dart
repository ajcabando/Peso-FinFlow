import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// A gradient-ring circular progress card with a centre label — used for
/// budget totals and savings goals.
class CircularChartCard extends StatelessWidget {
  const CircularChartCard({
    super.key,
    required this.progress,
    required this.centerTitle,
    required this.centerValue,
    required this.centerSubtitle,
    this.trackColor,
    this.progressColors,
    this.size = 150,
  });

  /// 0.0 – 1.0 fraction of the ring to fill.
  final double progress;

  final String centerTitle;
  final String centerValue;
  final String centerSubtitle;

  final Color? trackColor;
  final List<Color>? progressColors;

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final clamped = progress.clamp(0.0, 1.0);
    final colors =
        progressColors ??
        [theme.colorScheme.primary, theme.colorScheme.tertiary];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // Dark mode: the disc blends into the card with a hairline-white
        // ring track; light mode keeps the soft M3 surface tones.
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : theme.colorScheme.surfaceContainerLowest,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _RingPainter(
          progress: clamped,
          // The ring track needs slightly more presence than chart bar
          // tracks ([AppColors.chartTrack] uses 0.05), so it gets its own
          // 0.10 white hairline in dark mode.
          trackColor: trackColor ??
              (isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : theme.colorScheme.surfaceContainerHighest),
          colors: colors,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerTitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                centerValue,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  centerSubtitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.colors,
  });

  final double progress;
  final Color trackColor;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);

    if (progress <= 0) return;

    final gradient = SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: -math.pi / 2 + 2 * math.pi,
      colors: colors,
    ).createShader(rect);

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = gradient;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.colors != colors;
}
