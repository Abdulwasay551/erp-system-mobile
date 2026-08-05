// Basic smoke test: with no stored session, the app should land on the login screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_pos/main.dart';

void main() {
  testWidgets('Shows login screen when not authenticated', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Mobile Corner ERP'), findsOneWidget);
    expect(find.text('Sign in to your shop account'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });
}
