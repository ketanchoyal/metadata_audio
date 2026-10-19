// Smoke test for the example app shell.
//
// Verifies the main layout renders: the sidebar header, the Local/Remote
// tabs, and the parser configuration switches.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('app shell renders tabs and parser configuration', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Sidebar header.
    expect(find.text('Metadata Audio'), findsOneWidget);

    // Navigation tabs for local vs remote parsing.
    expect(find.text('Local File'), findsOneWidget);
    expect(find.text('Remote URL'), findsOneWidget);

    // Parser configuration switches.
    expect(find.text('Extract Chapters'), findsOneWidget);
    expect(find.text('Calculate Duration'), findsOneWidget);
    expect(find.text('Skip Cover Images'), findsOneWidget);
    expect(find.text('Skip Post Headers'), findsOneWidget);
    expect(find.text('Use MKV SeekHead Index'), findsOneWidget);
    expect(find.text('Max In-Memory Buffer'), findsOneWidget);
  });

  testWidgets('supported formats button lists MIME types', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // The button sits lower in the (scrollable) sidebar; make it visible.
    await tester.ensureVisible(find.textContaining('Supported formats:'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Supported formats:'));
    await tester.pumpAndSettle();

    // The dialog shows the title and contains at least one MIME type.
    expect(find.text('Supported Formats'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });
}
