import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/components/manager/script_manager.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/utils/har.dart';

void main() {
  test('console output is kept on the matching request and execution phase', () {
    final first = HttpRequest(HttpMethod.get, 'https://example.com/first');
    final second = HttpRequest(HttpMethod.get, 'https://example.com/second');
    final args = <dynamic>['log', 'request', 42];

    ScriptManager.captureConsoleLog(first, 'first script', args);
    ScriptManager.captureConsoleLog(first, 'first script', ['error', 'response failed'], response: true);
    ScriptManager.captureConsoleLog(second, 'second script', ['warn', 'other request']);

    expect(args, ['log', 'request', 42]);
    expect(first.requestScriptLogs.single.output, 'request 42');
    expect(first.requestScriptLogs.single.scriptName, 'first script');
    expect(first.responseScriptLogs.single.level, 'error');
    expect(second.requestScriptLogs.single.output, 'other request');
    expect(second.responseScriptLogs, isEmpty);
    expect(first.copy().requestScriptLogs, isEmpty);
    expect(first.copy().responseScriptLogs, isEmpty);
  });

  test('request JSON and HAR retain request and response console output', () {
    final request = HttpRequest(HttpMethod.get, 'https://example.com/data');
    final response = HttpResponse(HttpStatus.ok)..request = request;
    request.response = response;
    final time = DateTime.fromMillisecondsSinceEpoch(1710000000000);
    request.requestScriptLogs.add(ScriptConsoleEntry('log', 'before', scriptName: 'rewrite', time: time));
    request.responseScriptLogs.add(ScriptConsoleEntry('warn', 'after', scriptName: 'rewrite', time: time));

    final restoredJson = HttpRequest.fromJson(request.toJson());
    final restoredHar = Har.toRequest(Har.toHar(request));

    for (final restored in [restoredJson, restoredHar]) {
      expect(restored.requestScriptLogs.single.output, 'before');
      expect(restored.requestScriptLogs.single.scriptName, 'rewrite');
      expect(restored.responseScriptLogs.single.output, 'after');
      expect(restored.responseScriptLogs.single.time.millisecondsSinceEpoch, 1710000000000);
    }
  });

  test('history update replaces an earlier request snapshot without changing order', () async {
    final directory = await Directory.systemTemp.createTemp('proxypin-script-console-');
    final file = File('${directory.path}${Platform.pathSeparator}history.txt');
    try {
      final first = HttpRequest(HttpMethod.get, 'https://example.com/first');
      final second = HttpRequest(HttpMethod.get, 'https://example.com/second');
      final original = Har.toHar(first);
      first.responseScriptLogs.add(ScriptConsoleEntry('log', 'late response'));
      final update = Har.toHar(first)..['_historyUpdate'] = true;
      await file.writeAsString('${jsonEncode(original)},\n${jsonEncode(Har.toHar(second))},\n${jsonEncode(update)},\n');

      final restored = await Har.readFile(file);
      expect(restored, hasLength(2));
      expect(restored.first.requestId, first.requestId);
      expect(restored.first.responseScriptLogs.single.output, 'late response');
      expect(restored.last.requestId, second.requestId);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('imported console entry without a valid timestamp still loads', () {
    final entry = ScriptConsoleEntry.fromJson({'level': 'log', 'output': 'old entry', 'time': 'invalid'});
    expect(entry.output, 'old entry');
    expect(entry.time, isA<DateTime>());
  });
}
