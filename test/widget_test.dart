// This is a basic Flutter widget test for i-Share app

import 'package:flutter_test/flutter_test.dart';

import 'package:i_share/main.dart';

void main() {
  testWidgets('Splash screen loads', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const IShareApp());

    // Verify that i-Share text is present
    expect(find.text('i-Share'), findsOneWidget);
  });
}
