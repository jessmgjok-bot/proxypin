import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:proxypin/network/util/file_read.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A portable backup of application settings. Traffic and certificates are excluded.
class SettingsBackup {
  static const _kind = 'proxypin-settings';
  static const _version = 1;
  static const _supportConfigs = [
    'hosts.json',
    'request_map.json',
    'script.json',
    'request_breakpoint.json',
    'request_block.json',
    'report_servers.json',
    'network_condition.json',
    'environments.json',
  ];
  static const _dotConfigs = [
    'config.cnf',
    'request_rewrite.json',
    'request_crypto.json',
  ];
  static const _preferenceKeys = [
    'highlightEnabled',
    'highlightKeywords',
    'customerRepeat',
    'remoteDeviceList',
  ];

  static Future<Uint8List> exportBytes({String? supportDirectory, String? configDirectory}) async {
    final support = supportDirectory ?? (await getApplicationSupportDirectory()).path;
    final dot = configDirectory ?? (await FileRead.homeDir()).path;
    final configs = <String, dynamic>{};
    final files = <String, dynamic>{};
    final bodyFiles = <String, String>{};

    for (final name in [..._supportConfigs, ..._dotConfigs, 'ui_config.json']) {
      final base = _configBase(name, support, dot);
      final file = File(_join(base, name));
      final content = await file.exists() ? await file.readAsString() : '';
      configs[name] = content.trim().isEmpty ? null : jsonDecode(content);
    }

    final proxy = configs['config.cnf'];
    if (proxy != null) _asMap(proxy, 'config.cnf').remove('port');
    final ui = configs['ui_config.json'];
    if (ui != null) _asMap(ui, 'ui_config.json').remove('mcpPort');

    await _exportReferencedFiles(configs, files, bodyFiles, support, dot);

    final prefs = await SharedPreferences.getInstance();
    final preferences = <String, dynamic>{
      for (final key in _preferenceKeys) key: prefs.get(key),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode({
      'kind': _kind,
      'version': _version,
      'configs': configs,
      'files': files,
      'bodyFiles': bodyFiles,
      'preferences': preferences,
    })));
  }

  /// Imported settings take effect after the app restarts.
  static Future<void> importBytes(Uint8List bytes, {String? supportDirectory, String? configDirectory}) async {
    final decoded = jsonDecode(utf8.decode(bytes));
    final backup = _asMap(decoded, 'backup');
    if (backup['kind'] != _kind || backup['version'] != _version) {
      throw const FormatException('Unsupported settings backup');
    }
    final configs = _asMap(backup['configs'], 'configs');
    final files = _asMap(backup['files'], 'files');
    final bodyFiles = _asMap(backup['bodyFiles'], 'bodyFiles');
    final preferences = _asMap(backup['preferences'], 'preferences');
    final configNames = {..._supportConfigs, ..._dotConfigs, 'ui_config.json'};
    if (configs.keys.toSet().difference(configNames).isNotEmpty ||
        configNames.difference(configs.keys.toSet()).isNotEmpty) {
      throw const FormatException('Settings backup has an invalid config list');
    }
    if (preferences.keys.toSet().difference(_preferenceKeys.toSet()).isNotEmpty ||
        _preferenceKeys.toSet().difference(preferences.keys.toSet()).isNotEmpty) {
      throw const FormatException('Settings backup has an invalid preference list');
    }
    _validatePreferences(preferences);
    for (final name in configNames) {
      final value = configs[name];
      if (value == null) continue;
      if (name == 'report_servers.json') {
        for (final entry in _asList(value, name)) {
          _asMap(entry, name);
        }
      } else {
        _asMap(value, name);
      }
    }
    for (final name in ['script.json', 'request_map.json']) {
      final config = _asMapOrNull(configs[name]);
      if (config != null && config['list'] == null) throw FormatException('Missing $name rules');
      _entries(config, 'list').toList();
    }
    _entries(_asMapOrNull(configs['request_rewrite.json']), 'rules').toList();
    if (_asMapOrNull(configs['config.cnf'])?.containsKey('port') == true ||
        _asMapOrNull(configs['ui_config.json'])?.containsKey('mcpPort') == true) {
      throw const FormatException('Settings backup must not contain local ports');
    }

    final support = supportDirectory ?? (await getApplicationSupportDirectory()).path;
    final dot = configDirectory ?? (await FileRead.homeDir()).path;
    final assetDir = _join(support, 'settings_backup_assets', DateTime.now().microsecondsSinceEpoch.toString());
    final usedFiles = <String>{};
    final usedBodyFiles = <String>{};
    final writes = <String, List<int>>{};
    _prepareReferencedFiles(configs, files, bodyFiles, usedFiles, usedBodyFiles, writes, support, dot, assetDir);
    if (files.keys.toSet().difference(usedFiles).isNotEmpty ||
        bodyFiles.keys.toSet().difference(usedBodyFiles).isNotEmpty) {
      throw const FormatException('Settings backup contains unexpected files');
    }

    for (final name in configNames) {
      final destination = _join(_configBase(name, support, dot), name);
      var value = configs[name];
      if (name == 'config.cnf' || name == 'ui_config.json') {
        final existing = await _readMapIfPresent(File(destination));
        final portKey = name == 'config.cnf' ? 'port' : 'mcpPort';
        final localPort = existing?[portKey];
        if (localPort != null) {
          value = {...?_asMapOrNull(value), portKey: localPort};
        }
      }
      if (value != null) writes[destination] = utf8.encode(jsonEncode(value));
    }

    final prefs = await SharedPreferences.getInstance();
    final previousPreferences = <String, Object?>{
      for (final key in _preferenceKeys)
        key: key == 'remoteDeviceList' ? prefs.getStringList(key)?.toList() : prefs.get(key),
    };
    final affectedPaths = <String>{
      ...writes.keys,
      for (final name in configNames) _join(_configBase(name, support, dot), name),
    };
    final previousFiles = <String, Uint8List?>{};
    for (final path in affectedPaths) {
      final file = File(path);
      previousFiles[path] = await file.exists() ? await file.readAsBytes() : null;
    }

    try {
      for (final entry in writes.entries) {
        final file = File(entry.key);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
      }
      for (final name in configNames) {
        final destination = _join(_configBase(name, support, dot), name);
        if (!writes.containsKey(destination)) {
          final file = File(destination);
          if (await file.exists()) await file.delete();
        }
      }
      for (final key in _preferenceKeys) {
        await _setPreference(prefs, key, preferences[key]);
      }
    } catch (error, stackTrace) {
      final rollbackErrors = <String>[];
      for (final entry in previousFiles.entries.toList().reversed) {
        try {
          final file = File(entry.key);
          if (entry.value == null) {
            if (await file.exists()) await file.delete();
          } else {
            await file.parent.create(recursive: true);
            await file.writeAsBytes(entry.value!, flush: true);
          }
        } catch (rollbackError) {
          rollbackErrors.add('${entry.key}: $rollbackError');
        }
      }
      for (final key in _preferenceKeys) {
        try {
          await _setPreference(prefs, key, previousPreferences[key]);
        } catch (rollbackError) {
          rollbackErrors.add('$key: $rollbackError');
        }
      }
      final suffix = rollbackErrors.isEmpty ? 'Previous settings restored.' : 'Rollback errors: ${rollbackErrors.join('; ')}';
      Error.throwWithStackTrace(StateError('Settings import failed: $error. $suffix'), stackTrace);
    }
  }

  static Future<void> _setPreference(SharedPreferences prefs, String key, Object? value) async {
    final bool saved;
    if (value == null) {
      saved = await prefs.remove(key);
    } else if (value is bool) {
      saved = await prefs.setBool(key, value);
    } else if (value is String) {
      saved = await prefs.setString(key, value);
    } else {
      saved = await prefs.setStringList(key, List<String>.from(value as List));
    }
    if (!saved) throw StateError('Could not save preference $key');
  }

  static Future<void> _exportReferencedFiles(Map<String, dynamic> configs, Map<String, dynamic> files,
      Map<String, String> bodyFiles, String support, String dot) async {
    Future<void> capture(String reference, String folder, String extension, String base, String prefix,
        {bool body = false}) async {
      final relative = _reference(reference, folder, extension);
      final key = '$prefix/$relative';
      if (files.containsKey(key)) return;
      final file = File(_join(base, relative.replaceAll('/', Platform.pathSeparator)));
      if (!await file.exists()) throw FormatException('Missing settings file: $reference');
      final content = await file.readAsString();
      final parsed = extension == '.js' ? content : jsonDecode(content);
      if (body) {
        if (folder == 'request_map') {
          await _captureBodyFile(_asMap(parsed, key), bodyFiles);
        } else {
          for (final item in _asList(parsed, key)) {
            final values = _asMap(item, key)['values'];
            if (values != null) await _captureBodyFile(_asMap(values, '$key values'), bodyFiles);
          }
        }
      }
      files[key] = parsed;
    }

    final scripts = _asMapOrNull(configs['script.json']);
    for (final item in _entries(scripts, 'list')) {
      final path = item['scriptPath'];
      if (path == null) continue;
      final relative = _reference(path, 'scripts', '.js');
      item['scriptPath'] = '/$relative';
      await capture(path, 'scripts', '.js', support, 'support');
    }
    final maps = _asMapOrNull(configs['request_map.json']);
    for (final item in _entries(maps, 'list')) {
      final path = item['itemPath'];
      if (path == null) continue;
      final relative = _reference(path, 'request_map', '.json');
      item['itemPath'] = '/$relative';
      await capture(path, 'request_map', '.json', support, 'support', body: true);
    }
    final rewrites = _asMapOrNull(configs['request_rewrite.json']);
    for (final item in _entries(rewrites, 'rules')) {
      final path = item['rewritePath'];
      if (path == null) continue;
      final relative = _reference(path, 'rewrite', '.json');
      item['rewritePath'] = '/$relative';
      await capture(path, 'rewrite', '.json', dot, 'dot', body: true);
    }
  }

  static Future<void> _captureBodyFile(Map<String, dynamic> item, Map<String, String> bodyFiles) async {
    final path = item['bodyFile'];
    if (path == null || path == '') return;
    if (path is! String) throw const FormatException('Invalid body file path');
    final id = 'body-${bodyFiles.length.toString().padLeft(4, '0')}.bin';
    try {
      bodyFiles[id] = base64Encode(await FileRead.readFile(path));
    } on FileSystemException {
      throw FormatException('Cannot read rule body file: $path');
    }
    item['bodyFile'] = 'backup://$id';
  }

  static void _prepareReferencedFiles(Map<String, dynamic> configs, Map<String, dynamic> files,
      Map<String, dynamic> bodyFiles, Set<String> usedFiles, Set<String> usedBodyFiles,
      Map<String, List<int>> writes, String support, String dot, String assetDir) {
    void restoreBody(Map<String, dynamic> item) {
      final path = item['bodyFile'];
      if (path == null || path == '') return;
      if (path is! String || !RegExp(r'^backup://body-[0-9]+\.bin$').hasMatch(path)) {
        throw const FormatException('Invalid backed up body file reference');
      }
      final id = path.substring('backup://'.length);
      final content = bodyFiles[id];
      if (content is! String) throw FormatException('Missing body file: $id');
      usedBodyFiles.add(id);
      writes[_join(assetDir, id)] = base64Decode(content);
      item['bodyFile'] = _join(assetDir, id);
    }

    void restore(String reference, String folder, String extension, String base, String prefix,
        {bool body = false}) {
      final relative = _reference(reference, folder, extension);
      final key = '$prefix/$relative';
      if (usedFiles.contains(key)) return;
      final content = files[key];
      if (content == null) throw FormatException('Missing settings file: $key');
      usedFiles.add(key);
      if (extension == '.js') {
        if (content is! String) throw FormatException('Invalid settings file: $key');
        writes[_join(base, relative.replaceAll('/', Platform.pathSeparator))] = utf8.encode(content);
      } else {
        if (body) {
          if (folder == 'request_map') {
            restoreBody(_asMap(content, key));
          } else {
            for (final item in _asList(content, key)) {
              final values = _asMap(item, key)['values'];
              if (values != null) restoreBody(_asMap(values, '$key values'));
            }
          }
        }
        writes[_join(base, relative.replaceAll('/', Platform.pathSeparator))] = utf8.encode(jsonEncode(content));
      }
    }

    for (final item in _entries(_asMapOrNull(configs['script.json']), 'list')) {
      final path = item['scriptPath'];
      if (path == null) continue;
      if (path is! String) throw const FormatException('Invalid script path');
      restore(path, 'scripts', '.js', support, 'support');
      item['scriptPath'] = Platform.pathSeparator + _reference(path, 'scripts', '.js').replaceAll('/', Platform.pathSeparator);
    }
    for (final item in _entries(_asMapOrNull(configs['request_map.json']), 'list')) {
      final path = item['itemPath'];
      if (path == null) continue;
      if (path is! String) throw const FormatException('Invalid map path');
      restore(path, 'request_map', '.json', support, 'support', body: true);
      item['itemPath'] = Platform.pathSeparator + _reference(path, 'request_map', '.json').replaceAll('/', Platform.pathSeparator);
    }
    for (final item in _entries(_asMapOrNull(configs['request_rewrite.json']), 'rules')) {
      final path = item['rewritePath'];
      if (path == null) continue;
      if (path is! String) throw const FormatException('Invalid rewrite path');
      restore(path, 'rewrite', '.json', dot, 'dot', body: true);
      item['rewritePath'] = Platform.pathSeparator + _reference(path, 'rewrite', '.json').replaceAll('/', Platform.pathSeparator);
    }
  }

  static String _reference(Object? value, String folder, String extension) {
    if (value is! String) throw const FormatException('Invalid settings file reference');
    final normalized = value.replaceAll('\\', '/').replaceFirst(RegExp(r'^/'), '');
    final parts = normalized.split('/');
    if (parts.length != 2 || parts[0] != folder ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(parts[1]) ||
        !parts[1].endsWith(extension)) {
      throw FormatException('Invalid settings file reference: $value');
    }
    return normalized;
  }

  static Iterable<Map<String, dynamic>> _entries(Map<String, dynamic>? config, String field) sync* {
    if (config == null) return;
    for (final value in _asList(config[field] ?? [], field)) {
      yield _asMap(value, field);
    }
  }

  static Map<String, dynamic> _asMap(Object? value, String field) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw FormatException('Invalid $field');
    }
    return value as Map<String, dynamic>;
  }

  static Map<String, dynamic>? _asMapOrNull(Object? value) => value == null ? null : _asMap(value, 'config');

  static List<dynamic> _asList(Object? value, String field) {
    if (value is! List) throw FormatException('Invalid $field');
    return value;
  }

  static void _validatePreferences(Map<String, dynamic> preferences) {
    for (final key in _preferenceKeys) {
      final value = preferences[key];
      if (value == null) continue;
      if (key == 'highlightEnabled' && value is bool) continue;
      if ((key == 'highlightKeywords' || key == 'customerRepeat') && value is String) continue;
      if (key == 'remoteDeviceList' && value is List && value.every((item) => item is String)) continue;
      throw FormatException('Invalid preference: $key');
    }
    for (final key in ['highlightKeywords', 'customerRepeat']) {
      final value = preferences[key];
      if (value != null) _asMap(jsonDecode(value as String), key);
    }
    for (final entry in preferences['remoteDeviceList'] as List? ?? []) {
      _asMap(jsonDecode(entry as String), 'remoteDeviceList');
    }
  }

  static Future<Map<String, dynamic>?> _readMapIfPresent(File file) async {
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    try {
      return _asMap(jsonDecode(content), file.path);
    } on FormatException {
      return null;
    }
  }

  static String _configBase(String name, String support, String dot) {
    if (name == 'ui_config.json') return Platforms.isDesktop() ? dot : support;
    return _dotConfigs.contains(name) ? dot : support;
  }

  static String _join(String base, String first, [String? second]) =>
      [base, first, if (second != null) second].join(Platform.pathSeparator);
}
