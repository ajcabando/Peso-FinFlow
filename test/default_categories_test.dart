import 'package:finflow/database/seed/default_categories.dart';
import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seeds a healthy mix of income and expense categories', () {
    final income = defaultCategories
        .where((c) => c.type == AccountType.income)
        .length;
    final expense = defaultCategories
        .where((c) => c.type == AccountType.expense)
        .length;

    expect(defaultCategories, isNotEmpty);
    expect(income, greaterThan(0));
    expect(expense, greaterThan(0));
    expect(income + expense, defaultCategories.length);
  });

  test('every default category has a unique colour', () {
    final values = {
      for (final category in defaultCategories) category.color.toARGB32(),
    };

    expect(
      values.length,
      defaultCategories.length,
      reason: 'Each default category must carry a distinct colour so '
          'category charts stay visually separated from the start.',
    );
  });

  test('every default category carries an icon code', () {
    for (final category in defaultCategories) {
      expect(category.iconCode, isNotEmpty, reason: category.name);
    }
  });
}
