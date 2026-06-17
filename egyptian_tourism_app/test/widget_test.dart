import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:egyptian_tourism_app/main.dart';
import 'package:egyptian_tourism_app/providers/language_provider.dart';

void main() {
  testWidgets('App loads correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    final languageProvider = LanguageProvider();
    await tester.pumpWidget(EgyptianTourismApp(languageProvider: languageProvider));

    // Verify the app has loaded
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
