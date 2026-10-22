import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/settings_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory support;
  late Directory config;

  File inDirectory(Directory directory, String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  Future<void> write(Directory directory, String name, Object content) async {
    final file = inDirectory(directory, name);
    await file.parent.create(recursive: true);
    await file.writeAsString(content is String ? content : jsonEncode(content));
  }

  Map<String, dynamic> decode(Uint8List bytes) =>
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

  Uint8List encode(Map<String, dynamic> value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('proxypin-settings-backup-');
    support = Directory('${temp.path}${Platform.pathSeparator}support');
    config = Directory('${temp.path}${Platform.pathSeparator}config');
    await support.create();
    await config.create();
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('round trip restores rules and body files while preserving local ports and certificates', () async {
    final body = inDirectory(temp, 'rule-body.bin');
    await body.writeAsBytes([0, 1, 2, 255]);
    await write(config, 'config.cnf', {'port': 9099, 'enableSocks5': true});
    await write(config, 'ui_config.json', {'mcpPort': 9127, 'mode': 'dark'});
    await write(config, 'request_rewrite.json', {
      'enabled': true,
      'rules': [
        {'rewritePath': '/rewrite/rewrite.json', 'url': '*'},
        {'rewritePath': '/rewrite/rewrite.json', 'url': 'example.com'}
      ],
    });
    await write(config, 'rewrite/rewrite.json', [
      {'values': {'bodyFile': body.path, 'bodyType': 'file'}}
    ]);
    await write(support, 'request_map.json', {
      'enabled': true,
      'list': [
        {'itemPath': '/request_map/map.json', 'url': '*'},
        {'itemPath': '/request_map/map.json', 'url': 'example.com'}
      ],
    });
    await write(support, 'request_map/map.json', {'bodyFile': body.path, 'bodyType': 'file'});
    await write(support, 'script.json', {
      'enabled': true,
      'list': [
        {'scriptPath': '/scripts/local.js', 'name': 'local'}
      ],
    });
    await write(support, 'scripts/local.js', 'async function onRequest() { return 7; }');
    await write(support, 'client_certificates.json', {'secret': 'keep'});
    await write(config, 'ca.pem', 'private certificate');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('highlightEnabled', false);
    await prefs.setString('highlightKeywords', '{"Red":"token"}');

    final backup = await SettingsBackup.exportBytes(
      supportDirectory: support.path,
      configDirectory: config.path,
    );
    final data = decode(backup);
    final configs = data['configs'] as Map<String, dynamic>;
    expect((configs['config.cnf'] as Map)['port'], isNull);
    expect((configs['ui_config.json'] as Map)['mcpPort'], isNull);
    expect(configs, isNot(contains('client_certificates.json')));
    expect(data['files'], containsPair('support/scripts/local.js',
        'async function onRequest() { return 7; }'));
    expect((data['bodyFiles'] as Map).length, 2);

    await write(config, 'config.cnf', {'port': 9191, 'enableSocks5': false});
    await write(config, 'ui_config.json', {'mcpPort': 9222, 'mode': 'light'});
    await write(support, 'request_map/map.json', {'body': 'changed'});
    await write(config, 'rewrite/rewrite.json', []);
    await write(support, 'scripts/local.js', 'changed');
    await write(support, 'hosts.json', {'stale': true});
    await write(support, 'histories.json', 'saved traffic');
    await prefs.setBool('highlightEnabled', true);

    await SettingsBackup.importBytes(
      backup,
      supportDirectory: support.path,
      configDirectory: config.path,
    );

    final restoredProxy = jsonDecode(await inDirectory(config, 'config.cnf').readAsString()) as Map;
    final restoredUi = jsonDecode(await inDirectory(config, 'ui_config.json').readAsString()) as Map;
    expect(restoredProxy, containsPair('port', 9191));
    expect(restoredProxy, containsPair('enableSocks5', true));
    expect(restoredUi, containsPair('mcpPort', 9222));
    expect(restoredUi, containsPair('mode', 'dark'));
    expect(await inDirectory(support, 'scripts/local.js').readAsString(),
        'async function onRequest() { return 7; }');

    final restoredMap = jsonDecode(await inDirectory(support, 'request_map/map.json').readAsString()) as Map;
    final restoredRewrite = jsonDecode(await inDirectory(config, 'rewrite/rewrite.json').readAsString()) as List;
    final mapBodyPath = restoredMap['bodyFile'] as String;
    final rewriteBodyPath = (restoredRewrite.single as Map)['values']['bodyFile'] as String;
    expect(await File(mapBodyPath).readAsBytes(), [0, 1, 2, 255]);
    expect(await File(rewriteBodyPath).readAsBytes(), [0, 1, 2, 255]);
    expect(await inDirectory(support, 'client_certificates.json').readAsString(), '{"secret":"keep"}');
    expect(await inDirectory(config, 'ca.pem').readAsString(), 'private certificate');
    expect(await inDirectory(support, 'hosts.json').exists(), isFalse);
    expect(await inDirectory(support, 'histories.json').readAsString(), 'saved traffic');
    expect(prefs.getBool('highlightEnabled'), false);
    expect(prefs.getString('highlightKeywords'), '{"Red":"token"}');
  });

  test('rejects malformed metadata and traversal before changing settings', () async {
    await write(config, 'config.cnf', {'port': 9099, 'startup': true});
    await write(support, 'script.json', {
      'list': [
        {'scriptPath': '/scripts/local.js'}
      ],
    });
    await write(support, 'scripts/local.js', 'original');
    final originalConfig = await inDirectory(config, 'config.cnf').readAsString();
    final backup = decode(await SettingsBackup.exportBytes(
      supportDirectory: support.path,
      configDirectory: config.path,
    ));

    for (final invalid in [
      {...backup, 'version': 99},
      {
        ...backup,
        'configs': {
          ...(backup['configs'] as Map<String, dynamic>),
          'script.json': {
            'list': [
              {'scriptPath': '/scripts/../outside.js'}
            ],
          },
        },
      },
      {
        ...backup,
        'configs': {
          ...(backup['configs'] as Map<String, dynamic>),
          'config.cnf': {'port': 1234},
        },
      },
    ]) {
      await expectLater(
        SettingsBackup.importBytes(
          encode(invalid),
          supportDirectory: support.path,
          configDirectory: config.path,
        ),
        throwsFormatException,
      );
      expect(await inDirectory(config, 'config.cnf').readAsString(), originalConfig);
      expect(await inDirectory(support, 'scripts/local.js').readAsString(), 'original');
      expect(await Directory('${support.path}${Platform.pathSeparator}settings_backup_assets').exists(), isFalse);
    }
  });

  test('restores earlier writes when a later config write fails', () async {
    await write(config, 'config.cnf', {'port': 9099, 'startup': true});
    await write(config, 'ui_config.json', {'mcpPort': 9127, 'mode': 'dark'});
    await write(support, 'script.json', {
      'enabled': true,
      'list': [
        {'scriptPath': '/scripts/local.js'}
      ],
    });
    await write(support, 'scripts/local.js', 'backup script');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('highlightEnabled', true);
    final backup = await SettingsBackup.exportBytes(
      supportDirectory: support.path,
      configDirectory: config.path,
    );

    await write(config, 'config.cnf', {'port': 9191, 'startup': false});
    await write(support, 'scripts/local.js', 'current script');
    await write(support, 'client_certificates.json', {'secret': 'current certificate'});
    await write(support, 'histories.json', 'current traffic');
    await prefs.setBool('highlightEnabled', false);
    final currentConfig = await inDirectory(config, 'config.cnf').readAsBytes();
    final currentScript = await inDirectory(support, 'scripts/local.js').readAsBytes();

    await inDirectory(config, 'ui_config.json').delete();
    final blocker = Directory('${config.path}${Platform.pathSeparator}ui_config.json');
    await blocker.create();

    await expectLater(
      SettingsBackup.importBytes(
        backup,
        supportDirectory: support.path,
        configDirectory: config.path,
      ),
      throwsA(isA<StateError>().having((error) => error.message, 'message', contains('Previous settings restored.'))),
    );

    expect(await inDirectory(config, 'config.cnf').readAsBytes(), currentConfig);
    expect(await inDirectory(support, 'scripts/local.js').readAsBytes(), currentScript);
    expect(prefs.getBool('highlightEnabled'), false);
    expect(await blocker.exists(), isTrue);
    expect(await inDirectory(support, 'client_certificates.json').readAsString(),
        '{"secret":"current certificate"}');
    expect(await inDirectory(support, 'histories.json').readAsString(), 'current traffic');
  });
}
