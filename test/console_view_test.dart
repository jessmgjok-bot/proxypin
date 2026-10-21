import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/json/json_text.dart';
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

    expect(find.byType(JsonText), findsOneWidget);
    expect(find.textContaining('status', findRichText: true), findsWidgets);
    expect(find.textContaining('needle', findRichText: true), findsWidgets);
    expect(find.text('plain output', findRichText: true), findsWidgets);

    await tester.tap(find.text('JSON'));
    await tester.pumpAndSettle();
    expect(find.byType(JsonViewer), findsOneWidget);

    await tester.tap(find.byTooltip('Search log').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'needle');
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'status');
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);

    await tester.tap(find.text('Text').first);
    await tester.pumpAndSettle();
    expect(find.byType(JsonViewer), findsNothing);
    expect(find.textContaining('{"status":"needle","count":2}', findRichText: true), findsWidgets);
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

    expect(find.byType(JsonText), findsOneWidget);
    expect(find.text('plain output', findRichText: true), findsNothing);
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('copy buttons copy the selected log or visible console output', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConsoleLogView([
          ScriptConsoleEntry('log', '{"id":1}'),
          ScriptConsoleEntry('log', 'second output'),
        ]),
      ),
    ));

    final searchButton = find.byTooltip('Search log').first;
    final copyButton = find.byTooltip('Copy log').first;
    expect(tester.getTopLeft(copyButton).dx, greaterThan(tester.getTopLeft(searchButton).dx));
    await tester.tap(copyButton);
    await tester.pump();
    expect(copied, '{"id":1}');

    await tester.tap(find.byTooltip('Copy console'));
    await tester.pump();
    expect(copied, '{"id":1}\nsecond output');
  });
}
