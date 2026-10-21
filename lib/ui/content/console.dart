import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/json/json_text.dart';
import 'package:proxypin/ui/component/json/json_viewer.dart';
import 'package:proxypin/ui/component/json/theme.dart';
import 'package:proxypin/ui/component/search/highlight_text.dart';
import 'package:proxypin/ui/component/search/search_controller.dart';
import 'package:proxypin/utils/lang.dart';

Future<void> _copyConsoleText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    FlutterToastr.show(AppLocalizations.of(context)?.copied ?? 'Copied', context);
  }
}

class ConsoleLogView extends StatefulWidget {
  final List<ScriptConsoleEntry> logs;

  const ConsoleLogView(this.logs, {super.key});

  @override
  State<ConsoleLogView> createState() => _ConsoleLogViewState();
}

class _ConsoleLogViewState extends State<ConsoleLogView> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  void _openSearch() {
    if (!_showSearch) setState(() => _showSearch = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _searchFocusNode.unfocus();
    _searchController.clear();
    setState(() => _showSearch = false);
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final logs = query.isEmpty
        ? widget.logs
        : widget.logs.where((entry) {
            return entry.output.toLowerCase().contains(query) ||
                entry.level.toLowerCase().contains(query) ||
                (entry.scriptName?.toLowerCase().contains(query) ?? false);
          }).toList();

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(Platform.isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
            const _OpenConsoleSearchIntent(),
        LogicalKeySet(LogicalKeyboardKey.escape): const _CloseConsoleSearchIntent(),
      },
      child: Actions(
        actions: {
          _OpenConsoleSearchIntent: CallbackAction<_OpenConsoleSearchIntent>(onInvoke: (_) {
            _openSearch();
            return null;
          }),
          _CloseConsoleSearchIntent: CallbackAction<_CloseConsoleSearchIntent>(onInvoke: (_) {
            if (_showSearch) _closeSearch();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Column(children: [
            Row(children: [
              if (_showSearch)
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: 'Search console',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: IconButton(
                        tooltip: 'Close search',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _closeSearch,
                      ),
                    ),
                  ),
                )
              else
                const Spacer(),
              if (query.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('${logs.length} / ${widget.logs.length}', style: Theme.of(context).textTheme.bodySmall),
                ),
              if (!_showSearch)
                IconButton(
                  tooltip: 'Search console',
                  icon: const Icon(Icons.search, size: 20),
                  onPressed: _openSearch,
                ),
              IconButton(
                tooltip: 'Copy console',
                icon: const Icon(Icons.copy_outlined, size: 20),
                onPressed: logs.isEmpty
                    ? null
                    : () => _copyConsoleText(context, logs.map((entry) => entry.output).join('\n')),
              ),
            ]),
            Expanded(
              child: logs.isEmpty
                  ? const Center(child: Text('No matching logs'))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      itemCount: logs.length,
                      separatorBuilder: (_, __) => const Divider(height: 14),
                      itemBuilder: (context, index) => _ConsoleEntryView(logs[index], key: ObjectKey(logs[index])),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _OpenConsoleSearchIntent extends Intent {
  const _OpenConsoleSearchIntent();
}

class _CloseConsoleSearchIntent extends Intent {
  const _CloseConsoleSearchIntent();
}

class _ConsoleEntryView extends StatefulWidget {
  final ScriptConsoleEntry entry;

  const _ConsoleEntryView(this.entry, {super.key});

  @override
  State<_ConsoleEntryView> createState() => _ConsoleEntryViewState();
}

class _ConsoleEntryViewState extends State<_ConsoleEntryView> with SingleTickerProviderStateMixin {
  final _searchController = SearchTextController();
  final _searchIconKey = GlobalKey();
  late final TabController _formatController;
  dynamic _jsonValue;
  bool _isJson = false;

  @override
  void initState() {
    super.initState();
    _formatController = TabController(length: 3, vsync: this)..addListener(_onFormatChanged);
    _parseOutput();
  }

  void _parseOutput() {
    try {
      _jsonValue = jsonDecode(widget.entry.output);
      _isJson = _jsonValue is Map<String, dynamic> || _jsonValue is List;
    } on FormatException {
      _jsonValue = null;
      _isJson = false;
    }
  }

  void _onFormatChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _ConsoleEntryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry != widget.entry) {
      _parseOutput();
      _formatController.removeListener(_onFormatChanged);
      _formatController.index = 0;
      _formatController.addListener(_onFormatChanged);
    }
  }

  @override
  void dispose() {
    _formatController.removeListener(_onFormatChanged);
    _formatController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    if (_searchController.isSearchOverlayVisible) {
      _searchController.closeSearch();
      return;
    }
    final renderBox = _searchIconKey.currentContext?.findRenderObject() as RenderBox?;
    final position = renderBox?.localToGlobal(Offset.zero);
    _searchController.showSearchOverlay(context,
        top: position == null ? 100 : (position.dy + (renderBox?.size.height ?? 0) + 8).clamp(100, 240).toDouble(),
        right: 10);
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final color = entry.level == 'error'
        ? Theme.of(context).colorScheme.error
        : entry.level == 'warn'
            ? Colors.orange
            : Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Wrap(spacing: 12, runSpacing: 4, children: [
          Text(entry.time.formatMillisecond(), style: TextStyle(fontSize: 11, color: color)),
          Text(entry.level.toUpperCase(), style: TextStyle(fontSize: 11, color: color)),
          if (entry.scriptName != null) Text(entry.scriptName!, style: TextStyle(fontSize: 11, color: color)),
        ])),
        IconButton(
          key: _searchIconKey,
          tooltip: 'Search log',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          icon: const Icon(Icons.search),
          onPressed: _toggleSearch,
        ),
        IconButton(
          tooltip: 'Copy log',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          icon: const Icon(Icons.copy_outlined),
          onPressed: () => _copyConsoleText(context, entry.output),
        ),
      ]),
      const SizedBox(height: 4),
      if (_isJson) ...[
        TabBar(
          controller: _formatController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: const TextStyle(fontSize: 12),
          tabs: const [
            Tab(text: 'JSON Text', height: 32),
            Tab(text: 'JSON', height: 32),
            Tab(text: 'Text', height: 32),
          ],
        ),
        const SizedBox(height: 6),
      ],
      if (_isJson && _formatController.index == 0)
        JsonText(
          json: _jsonValue,
          indent: '    ',
          colorTheme: ColorTheme.of(context),
          searchController: _searchController,
        )
      else if (_isJson && _formatController.index == 1)
        JsonViewer(_jsonValue, colorTheme: ColorTheme.of(context), searchController: _searchController)
      else
        HighlightTextWidget(
          text: entry.output,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          searchController: _searchController,
        ),
    ]);
  }
}
