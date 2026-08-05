import '../models/bill.dart';

/// Contract for the bills feature's data layer.
abstract interface class BillRepository {
  /// Every bill, reactive, ordered by due day of month.
  Stream<List<Bill>> watchBills();

  /// The bill with [id], if any.
  Future<Bill?> getById(String id);

  /// Creates a bill.
  ///
  /// Throws `ValidationException` when the name is empty, the amount is not
  /// positive, the currency is invalid or the due day is outside 1–31.
  Future<Bill> create({
    required String name,
    required int amountMinor,
    required String currencyCode,
    String? accountId,
    required int dueDayOfMonth,
    required int reminderDaysBefore,
  });

  /// Updates the editable fields of an existing bill.
  Future<Bill> update({
    required String id,
    required String name,
    required int amountMinor,
    required String currencyCode,
    String? accountId,
    required int dueDayOfMonth,
    required int reminderDaysBefore,
    required bool isActive,
  });

  /// Marks [id] as paid for the current month.
  ///
  /// Throws `NotFoundException` when the bill does not exist.
  Future<Bill> markPaid(String id);

  /// Deletes the bill with [id].
  ///
  /// Throws `NotFoundException` when the bill does not exist.
  Future<void> deleteBill(String id);
}
