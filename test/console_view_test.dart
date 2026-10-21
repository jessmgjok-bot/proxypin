import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/json/json_viewer.dart';
import 'package:proxypin/ui/content/console.dart';

void main() {
  testWidgets('console renders JSON as a tree and searches its keys and values', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConsoleLogView([
          ScriptConsoleEntry('log', '{"status":"needle","count":2}', scriptName: 'json script'),
          ScriptConsoleEntry('warn', 'plain output', scriptName: 'text script'),
        ]),
      ),
    ));

    expect(find.byType(JsonViewer), findsOneWidget);
    expect(find.textContaining('status', findRichText: true), findsWidgets);
    expect(find.textContaining('needle', findRichText: true), findsWidgets);
    expect(find.text('plain output', findRichText: true), findsWidgets);

    await tester.tap(find.byTooltip('Search log').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'needle');
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'status');
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);
  });

  testWidgets('console search filters logs by JSON output', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConsoleLogView([
          ScriptConsoleEntry('log', '{"status":"needle"}', scriptName: 'json script'),
          ScriptConsoleEntry('warn', 'plain output', scriptName: 'text script'),
        ]),
      ),
    ));

    await tester.tap(find.byTooltip('Search console'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'needle');
    await tester.pumpAndSettle();

    expect(find.byType(JsonViewer), findsOneWidget);
    expect(find.text('plain output', findRichText: true), findsNothing);
    expect(find.text('1 / 2'), findsOneWidget);
  });
}
