import 'package:flutter/material.dart';

import '../../core/extensions/num_extensions.dart';
import '../../core/theme/app_colors.dart';

enum AmountVariant { neutral, income, expense }

/// Renders a minor-unit amount with the currency symbol, coloured by variant:
/// income = green, expense = red, neutral = default text colour.
class AmountText extends StatelessWidget {
  const AmountText(
    this.minorAmount, {
    super.key,
    required this.currencyCode,
    this.variant = AmountVariant.neutral,
    this.showSign = false,
    this.style,
  });

  final int minorAmount;
  final String currencyCode;
  final AmountVariant variant;
  final bool showSign;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final textStyle =
        style ??
        Theme.of(
          context,
        ).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600);
    final color = switch (variant) {
      AmountVariant.neutral => textStyle.color,
      AmountVariant.income => AppColors.income,
      AmountVariant.expense => AppColors.expense,
    };
    final text = showSign
        ? minorAmount.asMoneySigned(currencyCode)
        : minorAmount.asMoney(currencyCode);

    return Text(
      text,
      style: textStyle.copyWith(color: color),
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
    );
  }
}
