import 'package:intl/intl.dart';

// Indian digit grouping: 2,89,502.00
final NumberFormat _inr = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);

String formatINR(double amount) => _inr.format(amount);
