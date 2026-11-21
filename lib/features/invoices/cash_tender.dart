/// Change owed on a cash payment. Null when [tendered] is blank or not a
/// number, so the form can just hide the line.
double? cashChange(double amount, String tendered) {
  final t = double.tryParse(tendered.replaceAll(',', '').trim());
  if (t == null) return null;
  return ((t - amount) * 100).roundToDouble() / 100;
}

/// What goes in the payment reference when the tech left it empty.
String cashReference(double tendered, double change) =>
    'Cash, tendered ${tendered.toStringAsFixed(2)}, '
    'change ${change.toStringAsFixed(2)}';

/// The ex-tax price that makes one line of qty 1 come to exactly [gross]
/// at [rate] (0.1 for 10%), the way ITFlow rounds: tax to the cent on the
/// rounded price. Null when no price lands on the cent.
double? priceForGross(double gross, double rate) {
  if (rate <= 0) return gross;
  int total(int priceCents) => priceCents + (priceCents * rate).round();
  final target = (gross * 100).round();
  final guess = (target / (1 + rate)).round();
  for (final c in [guess, guess - 1, guess + 1, guess - 2, guess + 2]) {
    if (total(c) == target) return c / 100;
  }
  return null;
}
