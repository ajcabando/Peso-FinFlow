import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/chart_utils.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../transactions/domain/models/net_worth_point.dart';

/// Animated Net Worth history line chart for the analytics page.
class NetWorthTrendChart extends StatelessWidget {
  const NetWorthTrendChart({
    super.key,
    required this.points,
    required this.currencyCode,
    this.height = 220,
  });

  /// Oldest first.
  final List<NetWorthPoint> points;
  final String currencyCode;
  final double height;

  bool get _hasData => points.any((p) => p.netWorthMinor != 0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final gridColor = AppColors.chartGrid(theme);

    if (!_hasData) {
      return AppCard(
        child: SizedBox(
          height: height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.show_chart_rounded,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Record income or expenses to see your\nnet worth history.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final values = [for (final p in points) p.netWorthMinor];
    final rawMin = values.reduce((a, b) => a < b ? a : b);
    final rawMax = values.reduce((a, b) => a > b ? a : b);
    final span = (rawMax - rawMin).abs().clamp(1, 1 << 62);
    final minY = rawMin - span * 0.15;
    final maxY = rawMax + span * 0.15;
    final scale = ChartUtils.forCurrency(currencyCode);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 20, 20, 8),
      child: SizedBox(
        height: height,
        child: LineChart(
          // Implicit animations hang the first frame on web (and this
          // machine's software-rendered simulators); render instantly.
          duration: Duration.zero,
          curve: Curves.easeOutCubic,
          LineChartData(
            minX: 0,
            maxX: (points.length - 1).toDouble(),
            minY: minY / scale,
            maxY: maxY / scale,
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                getTooltipItems: (spots) => [
                  for (final spot in spots)
                    LineTooltipItem(
                      '${ChartUtils.monthName(points[spot.x.toInt()].month)} '
                      '${points[spot.x.toInt()].year}\n'
                      '${CurrencyFormatter.format((spot.y * scale).round(), currencyCode)}',
                      TextStyle(
                        color: theme.colorScheme.onInverseSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) =>
                  FlLine(color: gridColor, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 48,
                  getTitlesWidget: (value, meta) => Text(
                    CurrencyFormatter.formatCompact(
                      (value * scale).round(),
                      currencyCode,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= points.length) {
                      return const SizedBox.shrink();
                    }
                    // Label every other month so the axis stays readable.
                    if (points.length > 6 && index.isOdd) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        ChartUtils.monthName(points[index].month),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (final (index, point) in points.indexed)
                    FlSpot(index.toDouble(), point.netWorthMinor / scale),
                ],
                isCurved: true,
                curveSmoothness: 0.25,
                color: primary,
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, barData, index) =>
                      FlDotCirclePainter(
                        radius: 3.5,
                        color: theme.colorScheme.surface,
                        strokeWidth: 2.5,
                        strokeColor: primary,
                      ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      primary.withValues(alpha: 0.28),
                      primary.withValues(alpha: 0.02),
                    ],
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
