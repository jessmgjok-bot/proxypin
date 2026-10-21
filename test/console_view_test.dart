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

    expect(find.byTooltip('Search console'), findsOneWidget);
    expect(find.byTooltip('Copy console'), findsOneWidget);
    expect(find.byTooltip('Search log'), findsNothing);
    expect(find.byTooltip('Copy log'), findsNothing);

    await tester.tap(find.byTooltip('Search console'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'needle');
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);
    final jsonViewer = tester.widget<JsonViewer>(find.byType(JsonViewer));
    expect(jsonViewer.searchController?.shouldSearch(), isTrue);
    expect(jsonViewer.searchController?.value.pattern, 'needle');

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

  testWidgets('single toolbar copies visible console output', (tester) async {
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

    final searchButton = find.byTooltip('Search console');
    final copyButton = find.byTooltip('Copy console');
    expect(searchButton, findsOneWidget);
    expect(copyButton, findsOneWidget);
    expect(find.byTooltip('Copy log'), findsNothing);
    expect(tester.getTopLeft(copyButton).dx, greaterThan(tester.getTopLeft(searchButton).dx));
    await tester.tap(copyButton);
    await tester.pump();
    expect(copied, '{"id":1}\nsecond output');

    await tester.tap(searchButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'second');
    await tester.pumpAndSettle();
    await tester.tap(copyButton);
    await tester.pump();
    expect(copied, 'second output');
  });
}
