import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../transactions/domain/models/category_spend.dart';

/// Donut chart with a ranked category breakdown for a period.
///
/// Used in the compact dashboard card (top categories, smaller chart) and in
/// the full analytics breakdowns. Slices are tappable (tooltip) and animate
/// on first appearance.
class CategorySpendSection extends StatefulWidget {
  const CategorySpendSection({
    super.key,
    required this.spends,
    required this.currencyCode,
    this.limit = 6,
    this.compact = false,
    this.emptyMessage = 'Add expenses to see where your money goes.',
  });

  /// Net category activity, largest first.
  final List<CategorySpend> spends;

  final String currencyCode;

  /// How many top categories to chart and list.
  final int limit;

  /// Compact dashboard variant: smaller donut, tighter rows.
  final bool compact;

  final String emptyMessage;

  @override
  State<CategorySpendSection> createState() => _CategorySpendSectionState();
}

class _CategorySpendSectionState extends State<CategorySpendSection> {
  int? _touchedIndex;

  List<CategorySpend> get _top => widget.spends.take(widget.limit).toList();

  CategorySpend? get _touched {
    final index = _touchedIndex;
    if (index == null || index >= _top.length) return null;
    return _top[index];
  }

  int get _total =>
      widget.spends.fold<int>(0, (sum, spend) => sum + spend.amountMinor);

  bool get _hasData => widget.spends.isNotEmpty;

  Color _colorFor(int index, CategorySpend spend) => spend.colorValue != 0
      ? Color(spend.colorValue)
      : AppColors.categoryPalette[index % AppColors.categoryPalette.length];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_hasData) {
      return AppCard(
        child: SizedBox(
          height: widget.compact ? 140 : 180,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.donut_large_rounded,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.emptyMessage,
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

    final donutSize = widget.compact ? 118.0 : 148.0;
    final top = _top;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: donutSize,
                height: donutSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      // Implicit animations hang the first frame on web (and
                      // this machine's software-rendered simulators).
                      duration: Duration.zero,
                      curve: Curves.easeOutCubic,
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: donutSize * 0.42,
                        startDegreeOffset: -90,
                        pieTouchData: PieTouchData(
                          touchCallback: (event, response) {
                            setState(() {
                              _touchedIndex =
                                  response?.touchedSection?.touchedSectionIndex;
                            });
                          },
                        ),
                        sections: [
                          for (final (index, spend) in top.indexed)
                            PieChartSectionData(
                              value: spend.amountMinor.toDouble(),
                              color: _colorFor(index, spend),
                              radius:
                                  donutSize * 0.26 +
                                  (_touchedIndex == index ? 5 : 0),
                              showTitle: false,
                            ),
                        ],
                      ),
                    ),
                    // The centre shows the total by default and swaps to the
                    // touched category's details on interaction. Content is
                    // capped to the donut hole (radius 0.42 * 2) so long
                    // names or amounts ellipsize instead of overlapping the
                    // ring (a bare Column would size to its natural width
                    // and bleed over the slices).
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: donutSize * 0.80,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _touched?.categoryName ?? 'TOTAL',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              CurrencyFormatter.format(
                                _touched?.amountMinor ?? _total,
                                widget.currencyCode,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${top.length} of ${widget.spends.length} '
                      'categor${widget.spends.length == 1 ? 'y' : 'ies'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Tap a slice to inspect',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final (index, spend) in top.indexed) ...[
            if (index > 0) const SizedBox(height: AppSpacing.sm),
            _CategoryRow(
              spend: spend,
              color: _colorFor(index, spend),
              currencyCode: widget.currencyCode,
              totalMinor: _total,
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.spend,
    required this.color,
    required this.currencyCode,
    required this.totalMinor,
  });

  final CategorySpend spend;
  final Color color;
  final String currencyCode;
  final int totalMinor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = totalMinor == 0 ? 0.0 : spend.amountMinor / totalMinor;

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            spend.categoryName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '${(percent * 100).round()}%',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          CurrencyFormatter.format(spend.amountMinor, currencyCode),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
