import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/chart_utils.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../transactions/domain/models/monthly_cash_flow.dart';

/// Interactive monthly income vs expense bar chart for the dashboard.
///
/// Bars are tappable (tooltip), touch-friendly on mobile, and animated on
/// first appearance.
class CashFlowChart extends StatefulWidget {
  const CashFlowChart({
    super.key,
    required this.flow,
    required this.currencyCode,
    this.height = 220,
  });

  final List<MonthlyCashFlow> flow;
  final String currencyCode;
  final double height;

  @override
  State<CashFlowChart> createState() => _CashFlowChartState();
}

class _CashFlowChartState extends State<CashFlowChart> {
  int? _touchedIndex;

  bool get _hasData =>
      widget.flow.any((f) => f.incomeMinor > 0 || f.expenseMinor > 0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gridColor = AppColors.chartGrid(theme);
    final trackColor = AppColors.chartTrack(theme);

    if (!_hasData) {
      return AppCard(
        child: SizedBox(
          height: widget.height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.bar_chart_rounded,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Add income and expenses to see your\nmonthly cash flow.',
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

    final maxValue = widget.flow.fold<int>(0, (max, f) {
      final m = f.incomeMinor > f.expenseMinor ? f.incomeMinor : f.expenseMinor;
      return m > max ? m : max;
    });
    final scale = ChartUtils.forCurrency(widget.currencyCode);
    final maxDouble = maxValue / scale;
    // Round up to a friendly axis ceiling.
    final ceiling = maxDouble <= 0 ? 1.0 : _ceilToNice(maxDouble);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: SizedBox(
        height: widget.height,
        child: BarChart(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: ceiling,
            minY: 0,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final isIncome = rodIndex == 0;
                  final label = isIncome ? 'Income' : 'Expense';
                  return BarTooltipItem(
                    '$label\n${CurrencyFormatter.format((rod.toY * scale).round(), widget.currencyCode)}',
                    TextStyle(
                      color: theme.colorScheme.onInverseSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
              touchCallback: (event, response) {
                setState(() {
                  _touchedIndex = response?.spot == null
                      ? null
                      : response!.spot!.touchedBarGroupIndex;
                });
              },
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
                  reservedSize: 44,
                  getTitlesWidget: (value, meta) => Text(
                    _compactAxis(value, widget.currencyCode),
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
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= widget.flow.length) {
                      return const SizedBox.shrink();
                    }
                    final month = widget.flow[index];
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        ChartUtils.monthName(month.month),
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
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: ceiling / 4,
              getDrawingHorizontalLine: (value) =>
                  FlLine(color: gridColor, strokeWidth: 1),
            ),
            barGroups: [
              for (var i = 0; i < widget.flow.length; i++)
                BarChartGroupData(
                  x: i,
                  barsSpace: 3,
                  barRods: [
                    BarChartRodData(
                      toY: widget.flow[i].incomeMinor / scale,
                      width: 9,
                      color: AppColors.income,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: ceiling,
                        color: trackColor,
                      ),
                    ),
                    BarChartRodData(
                      toY: widget.flow[i].expenseMinor / scale,
                      width: 9,
                      color: AppColors.expense,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: ceiling,
                        color: trackColor,
                      ),
                    ),
                  ],
                  showingTooltipIndicators: _touchedIndex == i ? [0] : const [],
                ),
            ],
          ),
        ),
      ),
    );
  }

  static double _ceilToNice(double value) {
    if (value <= 0) return 1;
    final digits = value.floorToDouble().toString().length;
    final magnitude = CurrencyFormatter.pow10(digits - 1).toDouble();
    final normalized = value / magnitude;
    final nice = normalized <= 1
        ? 1.0
        : normalized <= 2
        ? 2.0
        : normalized <= 5
        ? 5.0
        : 10.0;
    return nice * magnitude;
  }

  static String _compactAxis(double value, String currencyCode) {
    final minor = (value * ChartUtils.forCurrency(currencyCode)).round();
    return CurrencyFormatter.formatCompact(minor, currencyCode);
  }
}
