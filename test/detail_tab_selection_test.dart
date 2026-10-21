import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/content/panel.dart';

HttpRequest _request(String path, {bool withLogs = false}) {
  final request = HttpRequest(HttpMethod.get, 'https://example.com/$path');
  final response = HttpResponse(HttpStatus.ok)..request = request;
  request.response = response;
  if (withLogs) {
    request.requestScriptLogs.add(ScriptConsoleEntry('log', 'request $path'));
    request.responseScriptLogs.add(ScriptConsoleEntry('log', 'response $path'));
  }
  return request;
}

Finder _paneTabBar(int paneIndex) {
  final paneKey = ValueKey(paneIndex == 0 ? 'request-pane' : 'response-pane');
  return find.descendant(of: find.byKey(paneKey), matching: find.byType(TabBar)).first;
}

String _selectedPaneTab(WidgetTester tester, int paneIndex) {
  final tabBarFinder = _paneTabBar(paneIndex);
  final tabBar = tester.widget<TabBar>(tabBarFinder);
  final controller = tabBar.controller ?? DefaultTabController.of(tester.element(tabBarFinder));
  return (tabBar.tabs[controller.index] as Tab).text!;
}

Future<void> _selectPaneTab(WidgetTester tester, int paneIndex, String label) async {
  final tabBarFinder = _paneTabBar(paneIndex);
  await tester.tap(find.descendant(of: tabBarFinder, matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('request and response sub-tabs stay selected when the request changes', (tester) async {
    final configuration = await AppConfiguration.instance;
    final previousMode = configuration.detailLayoutMode;
    configuration.detailLayoutMode = 'vertical';
    addTearDown(() => configuration.detailLayoutMode = previousMode);

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final first = _request('first');
    final second = _request('second');
    final panel = NetworkTabController(httpRequest: first, httpResponse: first.response);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: panel,
    ));
    await tester.pumpAndSettle();

    await _selectPaneTab(tester, 0, 'Headers');
    await _selectPaneTab(tester, 1, 'Body');
    expect(_selectedPaneTab(tester, 0), 'Headers');
    expect(_selectedPaneTab(tester, 1), 'Body');

    panel.change(second, second.response);
    await tester.pumpAndSettle();

    expect(_selectedPaneTab(tester, 0), 'Headers');
    expect(_selectedPaneTab(tester, 1), 'Body');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Console selection returns after switching through a request without logs', (tester) async {
    final configuration = await AppConfiguration.instance;
    final previousMode = configuration.detailLayoutMode;
    configuration.detailLayoutMode = 'vertical';
    addTearDown(() => configuration.detailLayoutMode = previousMode);

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final logged = _request('logged', withLogs: true);
    final noLogs = _request('no-logs');
    final loggedAgain = _request('logged-again', withLogs: true);
    final panel = NetworkTabController(httpRequest: logged, httpResponse: logged.response);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: panel,
    ));
    await tester.pumpAndSettle();

    await _selectPaneTab(tester, 0, 'Console');
    await _selectPaneTab(tester, 1, 'Console');

    panel.change(noLogs, noLogs.response);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    panel.change(loggedAgain, loggedAgain.response);
    await tester.pumpAndSettle();
    expect(_selectedPaneTab(tester, 0), 'Console');
    expect(_selectedPaneTab(tester, 1), 'Console');
    expect(tester.takeException(), isNull);

    panel.change(noLogs, noLogs.response);
    await tester.pumpAndSettle();
    await _selectPaneTab(tester, 0, 'General');
    await _selectPaneTab(tester, 1, 'Raw');
    panel.change(logged, logged.response);
    await tester.pumpAndSettle();
    expect(_selectedPaneTab(tester, 0), 'General');
    expect(_selectedPaneTab(tester, 1), 'Raw');
  });
}
