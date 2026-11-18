import 'package:ferrule/features/assets/asset_model.dart';
import 'package:ferrule/features/assets/asset_repository.dart';
import 'package:ferrule/features/assets/assets_screen.dart';
import 'package:ferrule/features/clients/client_model.dart';
import 'package:ferrule/features/clients/client_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _rows = [
  Asset(id: 1, name: 'Acme laptop', clientId: 1),
  Asset(id: 2, name: 'Acme server', clientId: 1),
  Asset(id: 3, name: 'Other printer', clientId: 2),
];

Widget _app(Widget child) => ProviderScope(
      overrides: [
        assetsProvider.overrideWith((ref) async => _rows),
        // Old ITFlow ignores client_id and sends every row back.
        clientAssetsProvider.overrideWith((ref, id) async => _rows),
        clientProvider.overrideWith((ref, id) async => Client(id: id, name: 'Acme')),
      ],
      child: MaterialApp(home: child),
    );

void main() {
  testWidgets('client filter shows only that client\'s assets', (t) async {
    await t.pumpWidget(_app(const AssetsScreen(clientId: 1)));
    await t.pumpAndSettle();
    expect(find.text('Acme laptop'), findsOneWidget);
    expect(find.text('Acme server'), findsOneWidget);
    expect(find.text('Other printer'), findsNothing);
    expect(find.text('Assets: Acme'), findsOneWidget);
  });

  testWidgets('no filter shows every asset', (t) async {
    await t.pumpWidget(_app(const AssetsScreen()));
    await t.pumpAndSettle();
    expect(find.text('Other printer'), findsOneWidget);
    expect(find.text('Assets'), findsOneWidget);
  });
}
