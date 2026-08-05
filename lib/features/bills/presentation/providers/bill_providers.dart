import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../domain/models/bill.dart';

/// Every bill, reactive, ordered by due day of month.
final billsProvider = StreamProvider<List<Bill>>(
  (ref) => ref.watch(billRepositoryProvider).watchBills(),
);

/// Bills that currently need attention (overdue or due soon), reactive —
/// feeds the dashboard reminder card.
final billsNeedingAttentionProvider = StreamProvider<List<Bill>>((ref) {
  return ref
      .watch(billRepositoryProvider)
      .watchBills()
      .map((bills) => bills.where((b) => b.needsAttention).toList());
});
