import 'package:flutter/material.dart';

import '../../features/accounts/domain/enums/account_type.dart';

/// A single default category to seed.
class DefaultCategory {
  const DefaultCategory({
    required this.name,
    required this.type,
    required this.color,
    required this.iconCode,
  });

  final String name;

  /// `income` or `expense`.
  final AccountType type;
  final Color color;
  final String iconCode;
}

/// Categories every new FinFlow installation starts with. Users can rename,
/// recolor or add their own at any time — categories are just ledger accounts.
///
/// Every entry carries a **unique** colour so category charts and chips stay
/// visually distinct from day one (new categories added later get the next
/// free colour from the dynamic palette).
const List<DefaultCategory> defaultCategories = [
  // ---- Income (positive-leaning hues) ----
  DefaultCategory(
    name: 'Salary',
    type: AccountType.income,
    color: Color(0xFF16C784),
    iconCode: 'payments',
  ),
  DefaultCategory(
    name: 'Business',
    type: AccountType.income,
    color: Color(0xFF6D5DF6),
    iconCode: 'storefront',
  ),
  DefaultCategory(
    name: 'Bonus',
    type: AccountType.income,
    color: Color(0xFFF5A623),
    iconCode: 'card_giftcard',
  ),
  DefaultCategory(
    name: 'Interest',
    type: AccountType.income,
    color: Color(0xFF4E9BFF),
    iconCode: 'savings',
  ),
  DefaultCategory(
    name: 'Refund',
    type: AccountType.income,
    color: Color(0xFF14B8A6),
    iconCode: 'replay',
  ),
  DefaultCategory(
    name: 'Gift',
    type: AccountType.income,
    color: Color(0xFFFF5C8D),
    iconCode: 'redeem',
  ),
  DefaultCategory(
    name: 'Other Income',
    type: AccountType.income,
    color: Color(0xFF94A3B8),
    iconCode: 'more_horiz',
  ),
  // ---- Expense ----
  DefaultCategory(
    name: 'Food & Dining',
    type: AccountType.expense,
    color: Color(0xFFF97316),
    iconCode: 'restaurant',
  ),
  DefaultCategory(
    name: 'Transportation',
    type: AccountType.expense,
    color: Color(0xFF8B5CF6),
    iconCode: 'directions_bus',
  ),
  DefaultCategory(
    name: 'Fuel',
    type: AccountType.expense,
    color: Color(0xFFEA3943),
    iconCode: 'local_gas_station',
  ),
  DefaultCategory(
    name: 'Utilities',
    type: AccountType.expense,
    color: Color(0xFF2563EB),
    iconCode: 'bolt',
  ),
  DefaultCategory(
    name: 'Water',
    type: AccountType.expense,
    color: Color(0xFF0EA5E9),
    iconCode: 'water_drop',
  ),
  DefaultCategory(
    name: 'Electricity',
    type: AccountType.expense,
    color: Color(0xFFF59E0B),
    iconCode: 'lightbulb',
  ),
  DefaultCategory(
    name: 'Internet',
    type: AccountType.expense,
    color: Color(0xFF06B6D4),
    iconCode: 'wifi',
  ),
  DefaultCategory(
    name: 'Shopping',
    type: AccountType.expense,
    color: Color(0xFFEC4899),
    iconCode: 'shopping_bag',
  ),
  DefaultCategory(
    name: 'Healthcare',
    type: AccountType.expense,
    color: Color(0xFFDC2626),
    iconCode: 'medical_services',
  ),
  DefaultCategory(
    name: 'Education',
    type: AccountType.expense,
    color: Color(0xFF3B82F6),
    iconCode: 'school',
  ),
  DefaultCategory(
    name: 'Insurance',
    type: AccountType.expense,
    color: Color(0xFF10B981),
    iconCode: 'health_and_safety',
  ),
  DefaultCategory(
    name: 'Travel',
    type: AccountType.expense,
    color: Color(0xFF0D9488),
    iconCode: 'flight',
  ),
  DefaultCategory(
    name: 'Entertainment',
    type: AccountType.expense,
    color: Color(0xFFA855F7),
    iconCode: 'movie',
  ),
  DefaultCategory(
    name: 'Vehicle',
    type: AccountType.expense,
    color: Color(0xFF475569),
    iconCode: 'directions_car',
  ),
  DefaultCategory(
    name: 'Taxes',
    type: AccountType.expense,
    color: Color(0xFFB91C1C),
    iconCode: 'receipt_long',
  ),
  DefaultCategory(
    name: 'Subscriptions',
    type: AccountType.expense,
    color: Color(0xFF6366F1),
    iconCode: 'subscriptions',
  ),
  DefaultCategory(
    name: 'Loan Payments',
    type: AccountType.expense,
    color: Color(0xFFD97706),
    iconCode: 'payments',
  ),
  DefaultCategory(
    name: 'Other Expenses',
    type: AccountType.expense,
    color: Color(0xFF71717A),
    iconCode: 'more_horiz',
  ),
];
