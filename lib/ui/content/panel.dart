/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/search/highlight_text.dart';
import 'package:proxypin/ui/component/search/search_controller.dart';
import 'package:proxypin/ui/component/split_view.dart';
import 'package:proxypin/ui/component/state_component.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/content/web_socket.dart';
import 'package:proxypin/ui/content/mqtt.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/platform.dart';

import 'body.dart';
import 'console.dart';
import 'headers.dart';
import 'menu.dart';

///网络请求详情页
///@Author: wanghongen
class NetworkTabController extends StatefulWidget {
  static GlobalKey<NetworkTabState>? currentKey;
  final String? windowId;
  final ProxyServer? proxyServer;
  final ValueWrap<HttpRequest> request = ValueWrap();
  final ValueWrap<HttpResponse> response = ValueWrap();
  final Widget? title;
  final TextStyle? tabStyle;

  NetworkTabController(
      {HttpRequest? httpRequest,
      HttpResponse? httpResponse,
      this.title,
      this.tabStyle,
      this.proxyServer,
      this.windowId})
      : super(key: GlobalKey<NetworkTabState>()) {
    currentKey = key as GlobalKey<NetworkTabState>;
    request.set(httpRequest);
    response.set(httpResponse);
  }

  void change(HttpRequest? request, HttpResponse? response) {
    this.request.set(request);
    this.response.set(response);
    var state = key as GlobalKey<NetworkTabState>;
    state.currentState?.changeState();
  }

  void changeState() {
    var state = key as GlobalKey<NetworkTabState>;
    state.currentState?.changeState();
  }

  ///更新当前详情请求的响应，请求在详情页打开期间完成时刷新响应内容
  void updateResponse(HttpResponse? response) {
    var currentRequest = request.get();
    if (response?.request == null || currentRequest == null) {
      return;
    }
    if (currentRequest.requestId != response!.request!.requestId) {
      return;
    }
    this.response.set(response);
    changeState();
  }

  @override
  State<StatefulWidget> createState() {
    return NetworkTabState();
  }

  static NetworkTabController? get current => currentKey?.currentWidget as NetworkTabController?;
}

class NetworkTabState extends State<NetworkTabController> with TickerProviderStateMixin {
  late List<String> tabs;
  late bool _mqttTabs;

  final TextStyle textStyle = const TextStyle(fontSize: 14);
  late TabController _tabController;

  final GlobalKey<HttpBodyState> requestHttpBodyKey = GlobalKey<HttpBodyState>();
  final GlobalKey<HttpBodyState> responseHttpBodyKey = GlobalKey<HttpBodyState>();
  String _requestPaneTab = 'General';
  String _responsePaneTab = 'Raw';
  bool get _verticalLayout =>
      Platforms.isDesktop() && !_mqttTabs && AppConfiguration.current?.detailLayoutMode == 'vertical';

  void changeState() {
    final mqtt = widget.request.get()?.protocolVersion == 'MQTT';
    if (mqtt != _mqttTabs) {
      _tabController.dispose();
      _configureTabs(mqtt);
    }
    setState(() {});
  }

  void _configureTabs(bool mqtt) {
    _mqttTabs = mqtt;
    tabs = mqtt ? ['General', 'MQTT'] : ['General', 'Request', 'Response', 'Cookies'];
    _tabController = TabController(length: tabs.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index != 1) {
        requestHttpBodyKey.currentState?.hideSearchOverlay();
      }
      if (_tabController.index != 2) {
        responseHttpBodyKey.currentState?.hideSearchOverlay();
      }
    });
  }

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _configureTabs(widget.request.get()?.protocolVersion == 'MQTT');

    if (widget.windowId != null) {
      HardwareKeyboard.instance.addHandler(onKeyEvent);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    HardwareKeyboard.instance.removeHandler(onKeyEvent);
    super.dispose();
  }

  bool onKeyEvent(KeyEvent event) {
    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      HardwareKeyboard.instance.removeHandler(onKeyEvent);
      WindowController.fromWindowId(widget.windowId!).close();
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    bool isMqtt = widget.request.get()?.protocolVersion == 'MQTT';
    bool isWebSocket = widget.request.get()?.isWebSocket == true;
    bool isSse = widget.response.get()?.headers.contentType.toLowerCase().startsWith('text/event-stream') == true;
    bool isStreamMessages = isWebSocket || isSse;
    if (isMqtt) {
      tabs[tabs.length - 1] = 'MQTT';
    } else if (isSse) {
      tabs[tabs.length - 1] = "SSE";
    } else if (isWebSocket) {
      tabs[tabs.length - 1] = "WebSocket";
    } else {
      tabs[tabs.length - 1] = 'Cookies';
    }

    var tabBar = TabBar(
      padding: const EdgeInsets.only(bottom: 0),
      controller: _tabController,
      dividerColor: Theme.of(context).dividerColor.withValues(alpha: 0.15),
      labelPadding: const EdgeInsets.symmetric(horizontal: 10),
      tabs: tabs.map((title) => Tab(child: Text(title, style: widget.tabStyle, maxLines: 1))).toList(),
    );

    final vertical = _verticalLayout;
    final layoutMenu = PopupMenuButton<String>(
      tooltip: 'Detail layout',
      icon: Icon(vertical ? Icons.view_agenda_outlined : Icons.tab_outlined, size: 20),
      onSelected: (value) {
        final config = AppConfiguration.current;
        if (config == null) return;
        config.detailLayoutMode = value;
        config.flushConfig();
        requestHttpBodyKey.currentState?.hideSearchOverlay();
        responseHttpBodyKey.currentState?.hideSearchOverlay();
        setState(() {});
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(value: 'tabs', checked: !vertical, child: const Text('Tabs')),
        CheckedPopupMenuItem(value: 'vertical', checked: vertical, child: const Text('Top / Bottom')),
      ],
    );

    final PreferredSizeWidget appBar;
    if (vertical) {
      appBar = AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 42,
        title: widget.title ?? const Text('Request / Response', style: TextStyle(fontSize: 15)),
        actions: [
          layoutMenu,
          if (widget.title != null) ...[
            ShareWidget(proxyServer: widget.proxyServer, request: widget.request.get(), response: widget.response.get()),
            DetailMenuWidget(request: widget.request.get()),
            const SizedBox(width: 10),
          ],
        ],
      );
    } else if (widget.title == null) {
      appBar = Platforms.isDesktop() && !isMqtt
          ? PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Row(children: [Expanded(child: tabBar), layoutMenu]),
            )
          : tabBar;
    } else {
      appBar = AppBar(
        title: widget.title,
        bottom: tabBar,
        centerTitle: true,
        actions: [
          if (Platforms.isDesktop() && !isMqtt) layoutMenu,
          ShareWidget(proxyServer: widget.proxyServer, request: widget.request.get(), response: widget.response.get()),
          const SizedBox(width: 3),
          DetailMenuWidget(request: widget.request.get()),
          const SizedBox(width: 10),
        ],
      );
    }

    return Scaffold(
      endDrawerEnableOpenDragGesture: false,
      appBar: appBar,
      body: vertical
          ? HorizontalSplitView(
              ratio: 0.5,
              minRatio: 0.2,
              maxRatio: 0.8,
              top: _TrafficPane(
                key: const ValueKey('request-pane'),
                requestPane: true,
                preferredTab: _requestPaneTab,
                onTabSelected: (label) => _requestPaneTab = label,
                request: widget.request,
                response: widget.response,
                hideRequestRewrite: widget.windowId != null,
              ),
              bottom: _TrafficPane(
                key: const ValueKey('response-pane'),
                requestPane: false,
                preferredTab: _responsePaneTab,
                onTabSelected: (label) => _responsePaneTab = label,
                request: widget.request,
                response: widget.response,
                hideRequestRewrite: widget.windowId != null,
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 10),
              child: TabBarView(
                physics: Platforms.isDesktop() ? const NeverScrollableScrollPhysics() : null, //桌面禁止滑动
                controller: _tabController,
                children: isMqtt
                    ? [
                        SelectionArea(child: General(widget.request, widget.response)),
                        SelectionArea(child: MqttMessages(widget.request)),
                      ]
                    : [
                        SelectionArea(child: General(widget.request, widget.response)),
                        KeepAliveWrapper(child: request()),
                        KeepAliveWrapper(child: response()),
                        SelectionArea(
                            child: isStreamMessages
                                ? Websocket(widget.request, widget.response)
                                : Cookies(widget.request, widget.response)),
                      ],
              )),
    );
  }

  Widget request() {
    if (widget.request.get() == null) {
      return const SizedBox();
    }

    var scrollController = ScrollController(); //处理body也有滚动条问题
    var path = widget.request.get()?.path ?? '';
    try {
      path = Uri.decodeFull(path);
    } catch (_) {}

    final details = SingleChildScrollView(
        controller: scrollController,
        child: Column(children: [
          RowWidget("Path", path),
          RequestParams(widget.request),
          ...message(widget.request.get(), "Request", scrollController)
        ]));
    return _withConsole(details, widget.request.get()!.requestScriptLogs);
  }

  Widget response() {
    if (widget.response.get() == null) {
      return const SizedBox();
    }

    var scrollController = ScrollController();
    final details = SingleChildScrollView(
        controller: scrollController,
        child: Column(children: [
          RowWidget("StatusCode", widget.response.get()?.status.toString()),
          ...message(widget.response.get(), "Response", scrollController)
        ]));
    return _withConsole(details, widget.request.get()?.responseScriptLogs ?? const []);
  }

  Widget _withConsole(Widget details, List<ScriptConsoleEntry> logs) {
    if (logs.isEmpty) return details;
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        const TabBar(tabs: [Tab(text: 'Details', height: 36), Tab(text: 'Console', height: 36)]),
        Expanded(
          child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
            children: [details, ConsoleLogView(logs, key: ValueKey(widget.request.get()?.requestId))],
          ),
        ),
      ]),
    );
  }

  List<Widget> message(HttpMessage? message, String type, ScrollController scrollController) {
    Widget bodyWidgets = HttpBodyWidget(
        key: type == "Request" ? requestHttpBodyKey : responseHttpBodyKey,
        hideRequestRewrite: widget.windowId != null,
        httpMessage: message,
        scrollController: scrollController);

    return [HeadersWidget(title: type, message: message, valueTextStyle: textStyle), bodyWidgets];
  }
}

class _TrafficPane extends StatefulWidget {
  final bool requestPane;
  final String preferredTab;
  final ValueChanged<String> onTabSelected;
  final ValueWrap<HttpRequest> request;
  final ValueWrap<HttpResponse> response;
  final bool hideRequestRewrite;

  const _TrafficPane({
    super.key,
    required this.requestPane,
    required this.preferredTab,
    required this.onTabSelected,
    required this.request,
    required this.response,
    required this.hideRequestRewrite,
  });

  @override
  State<_TrafficPane> createState() => _TrafficPaneState();
}

class _TrafficPaneState extends State<_TrafficPane> with TickerProviderStateMixin {
  late TabController _tabController;
  late List<String> _labels;
  late String _preferredLabel;

  List<String> _availableLabels() {
    final httpRequest = widget.request.get();
    final httpResponse = widget.response.get();
    final logs = widget.requestPane ? httpRequest?.requestScriptLogs : httpRequest?.responseScriptLogs;
    final streamMessages = httpRequest?.isWebSocket == true ||
        httpResponse?.headers.contentType.toLowerCase().startsWith('text/event-stream') == true;
    final streamTitle = httpRequest?.isWebSocket == true ? 'WebSocket' : 'SSE';
    return widget.requestPane
        ? ['General', 'Raw', 'Headers', 'Body', if (logs?.isNotEmpty == true) 'Console']
        : [
            'Raw',
            'Headers',
            'Body',
            streamMessages ? streamTitle : 'Cookies',
            if (logs?.isNotEmpty == true) 'Console',
          ];
  }

  void _createTabController(List<String> labels) {
    _labels = labels;
    final preferredIndex = labels.indexOf(_preferredLabel);
    _tabController = TabController(
      length: labels.length,
      initialIndex: preferredIndex < 0 ? 0 : preferredIndex,
      vsync: this,
    )..addListener(_rememberSelectedTab);
  }

  void _selectTab(int index) {
    if (index >= 0 && index < _labels.length) {
      final label = _labels[index];
      if (label == _preferredLabel) return;
      _preferredLabel = label;
      widget.onTabSelected(label);
    }
  }

  void _rememberSelectedTab() => _selectTab(_tabController.index);

  @override
  void initState() {
    super.initState();
    _preferredLabel = widget.preferredTab;
    _createTabController(_availableLabels());
  }

  @override
  void didUpdateWidget(covariant _TrafficPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final labels = _availableLabels();
    if (!listEquals(labels, _labels)) {
      final oldController = _tabController;
      oldController.removeListener(_rememberSelectedTab);
      _createTabController(labels);
      oldController.dispose();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final httpRequest = widget.request.get();
    final httpResponse = widget.response.get();
    final message = widget.requestPane ? httpRequest : httpResponse;
    final logs = widget.requestPane ? httpRequest?.requestScriptLogs : httpRequest?.responseScriptLogs;
    final streamMessages = httpRequest?.isWebSocket == true ||
        httpResponse?.headers.contentType.toLowerCase().startsWith('text/event-stream') == true;
    final labels = _labels;
    final pages = widget.requestPane
        ? <Widget>[
            General(widget.request, widget.response),
            _raw(message),
            _headers(message),
            _body(message),
            if (logs?.isNotEmpty == true)
              ConsoleLogView(logs!, key: ValueKey(httpRequest?.requestId)),
          ]
        : <Widget>[
            _raw(message),
            _headers(message),
            _body(message),
            streamMessages ? Websocket(widget.request, widget.response) : Cookies(widget.request, widget.response),
            if (logs?.isNotEmpty == true)
              ConsoleLogView(logs!, key: ValueKey(httpRequest?.requestId)),
          ];

    return Column(children: [
        Row(children: [
          Expanded(
            child: TabBar(
              controller: _tabController,
              onTap: _selectTab,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              dividerColor: Theme.of(context).dividerColor.withValues(alpha: 0.25),
              tabs: labels.map((label) => Tab(text: label, height: 38)).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              widget.requestPane ? (httpRequest?.method.name ?? '') : (httpResponse?.status.code.toString() ?? ''),
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ]),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: pages,
          ),
        ),
      ]);
  }

  Widget _raw(HttpMessage? message) {
    if (message == null) return const Center(child: Text('Waiting for response'));
    final text = StringBuffer();
    if (message is HttpRequest) {
      text.writeln('${message.method.name} ${message.pathAndQuery} ${message.protocolVersion}');
    } else if (message is HttpResponse) {
      text.writeln('${message.protocolVersion} ${message.status}');
    }
    message.headers.forEach((name, values) {
      for (final value in values) {
        text.writeln('$name: $value');
      }
    });
    if (message.body?.isNotEmpty == true) {
      text.writeln();
      if (message.contentType.isBinary) {
        text.write('[binary body]');
      } else if (message.body!.length > 128 * 1024) {
        text.write('[body exceeds 128 KB; open the Body tab to inspect it]');
      } else {
        final body = message.bodyAsString;
        text.write(body.length > 256 * 1024
            ? '${body.substring(0, 256 * 1024)}\n[truncated; open the Body tab]'
            : body);
      }
    }
    return _RawTextPanel(text: text.toString());
  }

  Widget _headers(HttpMessage? message) {
    if (message == null) return const Center(child: Text('Waiting for response'));
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: HeadersWidget(
        title: widget.requestPane ? 'Request' : 'Response',
        message: message,
        embedded: true,
      ),
    );
  }

  Widget _body(HttpMessage? message) {
    if (message == null) return const Center(child: Text('Waiting for response'));
    return SingleChildScrollView(
      key: ValueKey(message.requestId),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: HttpBodyWidget(httpMessage: message, hideRequestRewrite: widget.hideRequestRewrite),
    );
  }

}

class _RawTextPanel extends StatefulWidget {
  final String text;

  const _RawTextPanel({required this.text});

  @override
  State<_RawTextPanel> createState() => _RawTextPanelState();
}

class _RawTextPanelState extends State<_RawTextPanel> {
  final SearchTextController _searchController = SearchTextController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lineCount = '\n'.allMatches(widget.text).length + 1;
    final numbers = List.generate(lineCount, (index) => '${index + 1}').join('\n');
    final style = const TextStyle(fontSize: 13, fontFamily: 'monospace', height: 1.45);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: constraints.maxWidth > 1100 ? constraints.maxWidth - 32 : 1100,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                numbers,
                textAlign: TextAlign.right,
                style: style.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: HighlightTextWidget(
                  text: widget.text,
                  language: 'http',
                  style: style,
                  searchController: _searchController,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

Widget expansionTile(String title, List<Widget> content,
    {bool initiallyExpanded = true, ValueChanged<bool>? onExpansionChanged}) {
  return ExpansionTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
      tilePadding: const EdgeInsets.only(left: 0),
      expandedAlignment: Alignment.topLeft,
      initiallyExpanded: initiallyExpanded,
      onExpansionChanged: onExpansionChanged,
      shape: const Border(),
      children: content);
}

class RequestParams extends StatelessWidget {
  static bool initiallyExpanded = false;

  final ValueWrap<HttpRequest> request;

  const RequestParams(this.request, {super.key});

  @override
  Widget build(BuildContext context) {
    var request = this.request.get();
    if (request == null) {
      return const SizedBox();
    }
    var params = request.requestUri?.queryParametersAll;
    if (params == null || params.isEmpty) {
      return const SizedBox();
    }
    var content = <Widget>[];
    params.forEach((name, values) {
      for (var val in values) {
        content.add(RowWidget(name, val));
        content.add(const Divider(thickness: 0.1, height: 10));
      }
    });

    return expansionTile("Request Params", content, initiallyExpanded: initiallyExpanded,
        onExpansionChanged: (expanded) {
      //保存展开状态
      initiallyExpanded = expanded;
    });
  }
}

class General extends StatelessWidget {
  final ValueWrap<HttpRequest> request;

  final ValueWrap<HttpResponse> response;

  const General(this.request, this.response, {super.key});

  @override
  Widget build(BuildContext context) {
    var request = this.request.get();
    if (request == null) {
      return const SizedBox();
    }
    var response = this.response.get();
    String requestUrl = request.requestUrl;
    try {
      requestUrl = Uri.decodeFull(request.requestUrl);
    } catch (_) {}
    if (request.protocolVersion == 'MQTT') {
      return ListView(children: [
        expansionTile('General', [
          const SizedBox(height: 10),
          RowWidget('Connection', requestUrl),
          const SizedBox(height: 15),
          RowWidget('Protocol', 'MQTT over TLS'),
          const SizedBox(height: 15),
          RowWidget('Packets', request.messages.length.toString()),
          const SizedBox(height: 15),
          RowWidget('Start Time', request.requestTime.formatMillisecond()),
          const SizedBox(height: 15),
          if (request.processInfo != null) RowWidget('App', request.processInfo!.name),
        ])
      ]);
    }
    var content = [
      const SizedBox(height: 10),
      RowWidget("Request URL", requestUrl),
      const SizedBox(height: 15),
      RowWidget("Request Method", request.method.name),
      const SizedBox(height: 15),
      RowWidget("Protocol", request.protocolVersion),
      const SizedBox(height: 15),
      RowWidget("Status Code", response?.status.toString()),
      const SizedBox(height: 15),
      RowWidget("Remote Address",
          '${response?.remoteHost ?? ''}${response?.remotePort == null ? '' : ':${response?.remotePort}'}'),
      const SizedBox(height: 15),
      RowWidget("Request Time", request.requestTime.formatMillisecond()),
      const SizedBox(height: 15),
      RowWidget("Duration", response?.costTime()),
      const SizedBox(height: 15),
      RowWidget("Request Content-Type", request.headers.contentType),
      const SizedBox(height: 15),
      RowWidget("Response Content-Type", response?.headers.contentType),
      const SizedBox(height: 15),
      RowWidget("Request Package", getPackage(request.packageSize)),
      const SizedBox(height: 15),
      RowWidget("Response Package", getPackage(response?.packageSize)),
      const SizedBox(height: 15),
    ];
    if (request.processInfo != null) {
      content.add(RowWidget("App", request.processInfo!.name));
      content.add(const SizedBox(height: 15));
    }

    return ListView(children: [expansionTile("General", content)]);
  }
}

class Cookies extends StatelessWidget {
  final ValueWrap<HttpRequest> request;

  final ValueWrap<HttpResponse> response;

  const Cookies(this.request, this.response, {super.key});

  @override
  Widget build(BuildContext context) {
    var requestCookie = request.get()?.cookies.expand((cookie) => _cookieWidget(cookie)!);

    var responseCookie = response.get()?.headers.getList("Set-Cookie")?.expand((e) => _cookieWidget(e)!);
    return ListView(children: [
      requestCookie == null ? const SizedBox() : expansionTile("Request Cookies", requestCookie.toList()),
      const SizedBox(height: 15),
      responseCookie == null ? const SizedBox() : expansionTile("Response Cookies", responseCookie.toList()),
    ]);
  }

  Iterable<Widget>? _cookieWidget(String? cookie) {
    var headers = <Widget>[];

    cookie?.split(";").map((e) => Strings.splitFirst(e, "=")).where((element) => element != null).forEach((e) {
      headers.add(RowWidget(e!.key.trim(), e.value));
      headers.add(const Divider(thickness: 0.1, height: 10));
    });

    return headers;
  }
}

class RowWidget extends StatelessWidget {
  final String name;
  final String? value;
  final TextStyle textStyle = const TextStyle(fontSize: 14);

  const RowWidget(this.name, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
          flex: 2,
          child: SelectableText(name,
              contextMenuBuilder: contextMenu,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: Colors.deepOrangeAccent))),
      Expanded(flex: 4, child: SelectableText(contextMenuBuilder: contextMenu, style: textStyle, value ?? ''))
    ]);
  }
}
