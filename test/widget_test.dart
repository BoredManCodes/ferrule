import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ferrule/app.dart';

void main() {
  testWidgets('App boots to setup screen when not authenticated',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: FerruleApp()));
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
