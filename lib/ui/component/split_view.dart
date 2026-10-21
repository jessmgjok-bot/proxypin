import 'package:flutter/material.dart';

class VerticalSplitView extends StatefulWidget {
  final Widget left;
  final Widget right;
  final double ratio;
  final double minRatio;
  final double maxRatio;
  final Function(double ratio)? onRatioChanged;

  const VerticalSplitView(
      {super.key,
      required this.left,
      required this.right,
      this.ratio = 0.5,
      this.minRatio = 0,
      this.maxRatio = 1,
      this.onRatioChanged})
      : assert(ratio >= 0 && ratio <= 1);

  @override
  State<VerticalSplitView> createState() => _VerticalSplitViewState();
}

class _VerticalSplitViewState extends State<VerticalSplitView> {
  final _dividerWidth = 10.0;

  //from 0-1
  late double _ratio;
  double _maxWidth = double.infinity;

  get _width1 => _ratio * _maxWidth;

  get _width2 => (1 - _ratio) * _maxWidth;

  @override
  void initState() {
    super.initState();
    _ratio = widget.ratio;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, BoxConstraints constraints) {
      if (_maxWidth != constraints.maxWidth) {
        _maxWidth = constraints.maxWidth - _dividerWidth;
      }

      return SizedBox(
        width: constraints.maxWidth,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: _width1 - 5,
              child: widget.left,
            ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: SizedBox(
                    width: _dividerWidth,
                    height: double.infinity,
                    child: (_ratio <= 0 || _ratio >= 1)
                        ? const Icon(Icons.drag_handle, size: 16)
                        : const VerticalDivider(thickness: 1),
                  )),
              onPanEnd: (DragEndDetails details) {
                widget.onRatioChanged?.call(_ratio);
              },
              onPanUpdate: (DragUpdateDetails details) {
                setState(() {
                  _ratio += details.delta.dx / _maxWidth;

                  if (_ratio > widget.maxRatio) {
                    _ratio = widget.maxRatio;
                  } else if (_ratio < widget.minRatio) {
                    _ratio = widget.minRatio;
                  }
                });
              },
            ),
            SizedBox(
              width: _width2,
              child: widget.right,
            ),
          ],
        ),
      );
    });
  }
}

class HorizontalSplitView extends StatefulWidget {
  final Widget top;
  final Widget bottom;
  final double ratio;
  final double minRatio;
  final double maxRatio;
  final ValueChanged<double>? onRatioChanged;

  const HorizontalSplitView({
    super.key,
    required this.top,
    required this.bottom,
    this.ratio = 0.5,
    this.minRatio = 0,
    this.maxRatio = 1,
    this.onRatioChanged,
  }) : assert(ratio >= 0 && ratio <= 1);

  @override
  State<HorizontalSplitView> createState() => _HorizontalSplitViewState();
}

class _HorizontalSplitViewState extends State<HorizontalSplitView> {
  static const double _dividerHeight = 10;
  late double _ratio;

  @override
  void initState() {
    super.initState();
    _ratio = widget.ratio;
  }

  @override
  void didUpdateWidget(covariant HorizontalSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ratio != widget.ratio) {
      _ratio = widget.ratio;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final availableHeight =
          constraints.maxHeight > _dividerHeight ? constraints.maxHeight - _dividerHeight : 0.0;
      return Column(children: [
        SizedBox(height: availableHeight * _ratio, child: widget.top),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (details) {
            if (availableHeight <= 0) return;
            setState(() {
              _ratio = (_ratio + details.delta.dy / availableHeight)
                  .clamp(widget.minRatio, widget.maxRatio);
            });
          },
          onVerticalDragEnd: (_) => widget.onRatioChanged?.call(_ratio),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeRow,
            child: SizedBox(
              height: _dividerHeight,
              width: double.infinity,
              child: const Divider(height: _dividerHeight, thickness: 1),
            ),
          ),
        ),
        SizedBox(height: availableHeight * (1 - _ratio), child: widget.bottom),
      ]);
    });
  }
}
