import 'package:flutter/material.dart';

import '../../domain/enums/account_type.dart';

/// Maps account types and stored icon codes to [IconData]. Kept in the
/// presentation layer so the domain stays pure Dart.
IconData accountTypeIcon(AccountType type) => switch (type) {
  AccountType.cash => Icons.payments_outlined,
  AccountType.bank => Icons.account_balance_outlined,
  AccountType.debitCard => Icons.credit_card_outlined,
  AccountType.creditCard => Icons.credit_card_rounded,
  AccountType.ewallet => Icons.account_balance_wallet_outlined,
  AccountType.paypal => Icons.payment_outlined,
  AccountType.crypto => Icons.currency_bitcoin,
  AccountType.investment => Icons.show_chart_rounded,
  AccountType.loan => Icons.receipt_long_outlined,
  AccountType.income => Icons.trending_up_rounded,
  AccountType.expense => Icons.trending_down_rounded,
  AccountType.openingBalance => Icons.flag_outlined,
};

const Map<String, IconData> _iconCodeMap = {
  'payments': Icons.payments_outlined,
  'storefront': Icons.storefront_outlined,
  'card_giftcard': Icons.card_giftcard,
  'savings': Icons.savings_outlined,
  'replay': Icons.replay,
  'redeem': Icons.redeem,
  'more_horiz': Icons.more_horiz,
  'restaurant': Icons.restaurant_outlined,
  'directions_bus': Icons.directions_bus_outlined,
  'local_gas_station': Icons.local_gas_station_outlined,
  'bolt': Icons.bolt,
  'water_drop': Icons.water_drop_outlined,
  'lightbulb': Icons.lightbulb_outlined,
  'wifi': Icons.wifi,
  'shopping_bag': Icons.shopping_bag_outlined,
  'medical_services': Icons.medical_services_outlined,
  'school': Icons.school_outlined,
  'health_and_safety': Icons.health_and_safety_outlined,
  'flight': Icons.flight,
  'movie': Icons.movie_outlined,
  'directions_car': Icons.directions_car_outlined,
  'receipt_long': Icons.receipt_long_outlined,
  'subscriptions': Icons.subscriptions_outlined,
};

/// Resolves a stored icon code (e.g. `restaurant`) to an [IconData],
/// falling back to [fallback] for unknown codes.
IconData iconFromCode(String? code, {required IconData fallback}) {
  if (code == null) return fallback;
  return _iconCodeMap[code] ?? fallback;
}

/// Icon codes offered in the category form's icon picker.
const List<String> categoryIconCodes = [
  'restaurant',
  'shopping_bag',
  'directions_bus',
  'local_gas_station',
  'bolt',
  'water_drop',
  'lightbulb',
  'wifi',
  'medical_services',
  'school',
  'health_and_safety',
  'flight',
  'movie',
  'directions_car',
  'receipt_long',
  'subscriptions',
  'storefront',
  'savings',
  'card_giftcard',
  'redeem',
  'payments',
  'more_horiz',
];
