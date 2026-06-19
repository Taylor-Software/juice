import 'package:flutter/material.dart';

import '../engine/sketch.dart';

const _paper = Color(0xFFFAF7F0);
const _palette = <int>[
  0xFF222222,
  0xFFD83A2A,
  0xFF2A6FD8,
  0xFF2E9E5B,
  0xFFFFFFFF,
];

/// Paints a [SketchData]'s strokes on a paper background (theme-independent so
/// stored colors render the same in light and dark mode).
class SketchPainter extends CustomPainter {
  const SketchPainter(this.data);
  final SketchData data;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _paper);
    final sx = data.canvasWidth == 0 ? 1.0 : size.width / data.canvasWidth;
    final sy = data.canvasHeight == 0 ? 1.0 : size.height / data.canvasHeight;
    for (final s in data.strokes) {
      if (s.points.isEmpty) continue;
      final paint = Paint()
        ..color = Color(s.color)
        ..strokeWidth = s.width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path()
        ..moveTo(s.points.first[0] * sx, s.points.first[1] * sy);
      for (final p in s.points.skip(1)) {
        path.lineTo(p[0] * sx, p[1] * sy);
      }
      // A single tap (one point) draws a dot.
      if (s.points.length == 1) {
        canvas.drawCircle(
            Offset(s.points.first[0] * sx, s.points.first[1] * sy),
            s.width / 2,
            paint..style = PaintingStyle.fill);
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(SketchPainter old) => old.data != data;
}

/// Full-screen freehand editor. Calls [onDone] with the drawing (or null on
/// cancel) and pops.
class SketchEditor extends StatefulWidget {
  const SketchEditor({super.key, this.initial, required this.onDone});
  final SketchData? initial;
  final void Function(SketchData? result) onDone;

  @override
  State<SketchEditor> createState() => _SketchEditorState();
}

class _SketchEditorState extends State<SketchEditor> {
  late List<SketchStroke> _strokes = [...?widget.initial?.strokes];
  List<List<double>> _current = [];
  int _color = _palette.first;
  double _width = 3;
  Size _canvas = const Size(1, 1);

  void _save() {
    widget.onDone(SketchData(
      canvasWidth: _canvas.width,
      canvasHeight: _canvas.height,
      strokes: _strokes,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final preview = SketchData(
      canvasWidth: _canvas.width,
      canvasHeight: _canvas.height,
      strokes: [
        ..._strokes,
        if (_current.isNotEmpty)
          SketchStroke(color: _color, width: _width, points: _current),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sketch'),
        leading: IconButton(
          key: const Key('sketch-cancel'),
          icon: const Icon(Icons.close),
          onPressed: () => widget.onDone(null),
        ),
        actions: [
          IconButton(
            key: const Key('sketch-undo'),
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() => _strokes.removeLast()),
          ),
          IconButton(
            key: const Key('sketch-clear'),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: () => setState(() {
              _strokes = [];
              _current = [];
            }),
          ),
          IconButton(
            key: const Key('sketch-save'),
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _save,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              _canvas = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                key: const Key('sketch-canvas'),
                onPanStart: (d) =>
                    setState(() => _current = [_xy(d.localPosition)]),
                onPanUpdate: (d) =>
                    setState(() => _current.add(_xy(d.localPosition))),
                onPanEnd: (_) => setState(() {
                  if (_current.isNotEmpty) {
                    _strokes.add(SketchStroke(
                        color: _color, width: _width, points: _current));
                  }
                  _current = [];
                }),
                child: CustomPaint(
                  painter: SketchPainter(preview),
                  size: Size.infinite,
                ),
              );
            }),
          ),
          _toolbar(),
        ],
      ),
    );
  }

  List<double> _xy(Offset o) => [o.dx, o.dy];

  Widget _toolbar() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              for (final c in _palette)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == c ? Colors.blue : Colors.black26,
                        width: _color == c ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.circle, size: _width <= 3 ? 22 : 14),
                tooltip: 'Thin',
                onPressed: () => setState(() => _width = 3),
              ),
              IconButton(
                icon: Icon(Icons.circle, size: _width > 3 ? 22 : 14),
                tooltip: 'Thick',
                onPressed: () => setState(() => _width = 8),
              ),
            ],
          ),
        ),
      );
}

/// Opens the editor full-screen; returns the drawing or null on cancel.
Future<SketchData?> showSketchEditor(BuildContext context,
    {SketchData? initial}) {
  return Navigator.of(context).push<SketchData>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => SketchEditor(
      initial: initial,
      onDone: (d) => Navigator.of(context).pop(d),
    ),
  ));
}
