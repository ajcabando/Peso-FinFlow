import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/models/bill.dart';

/// A pill showing a bill's derived status with a colour matched to how much
/// attention it needs.
class BillStatusChip extends StatelessWidget {
  const BillStatusChip({super.key, required this.status});

  final BillStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      BillStatus.overdue => ('Overdue', AppColors.expense),
      BillStatus.dueSoon => ('Due soon', AppColors.warning),
      BillStatus.paid => ('Paid', AppColors.income),
      BillStatus.upcoming => ('Upcoming', AppColors.info),
      BillStatus.paused => ('Paused', Theme.of(context).colorScheme.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
