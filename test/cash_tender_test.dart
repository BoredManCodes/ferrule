import 'package:ferrule/features/invoices/cash_tender.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('change due', () {
    expect(cashChange(42.5, '50'), 7.5);
    expect(cashChange(42.5, ''), isNull);
    expect(cashChange(42.5, 'abc'), isNull);
    expect(cashChange(42.5, '40'), -2.5);
    expect(cashChange(10, '1,000'), 990);
    expect(cashChange(19.99, '20'), 0.01);
  });

  test('cash reference', () {
    expect(cashReference(50, 7.5), 'Cash, tendered 50.00, change 7.50');
  });

  test('ex-tax price lands on the gross', () {
    expect(priceForGross(110, 0.1), 100);
    expect(priceForGross(50, 0), 50);
    // 45.45 + 4.55 = 50.00
    expect(priceForGross(50, 0.1), 45.45);
    for (final g in [1.0, 9.99, 33.33, 199.95, 1234.56]) {
      final p = priceForGross(g, 0.1);
      if (p == null) continue;
      final cents = (p * 100).round();
      expect(cents + (cents * 0.1).round(), (g * 100).round(), reason: '$g');
    }
  });
}
