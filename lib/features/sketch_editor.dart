import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

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

/// Active drawing tool.
enum _SketchTool { pen, eraser, line, rect, ellipse }

/// Paints a [SketchData]'s strokes on a paper background (theme-independent so
/// stored colors render the same in light and dark mode).
class SketchPainter extends CustomPainter {
  const SketchPainter(this.data, {this.background});
  final SketchData data;

  /// Optional background image (resolved from [SketchData.backgroundBlobId] by
  /// the widget layer); drawn fit-contained over the paper, under the strokes.
  final ui.Image? background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _paper);
    if (background != null) {
      paintImage(
        canvas: canvas,
        rect: Offset.zero & size,
        image: background!,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    }
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
  bool shouldRepaint(SketchPainter old) =>
      old.data != data || old.background != background;
}

/// Full-screen freehand editor. Calls [onDone] with the drawing (or null on
/// cancel) and pops.
class SketchEditor extends StatefulWidget {
  const SketchEditor({
    super.key,
    this.initial,
    this.background,
    this.backgroundBlobId,
    this.pdfBlobId,
    this.pdfPage,
    required this.onDone,
  });
  final SketchData? initial;

  /// Optional background image to annotate (resolved from a blob by the caller).
  final ui.Image? background;

  /// The blob id of [background], persisted on the saved [SketchData] so the
  /// image re-loads when the sketch is reopened.
  final String? backgroundBlobId;

  /// PDF-page provenance carried through onto the saved [SketchData].
  final String? pdfBlobId;
  final int? pdfPage;
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
  _SketchTool _tool = _SketchTool.pen;
  // Undo history: snapshots of [_strokes] taken before each mutation (draw,
  // erase, clear), so all three are undoable. Replaces a plain removeLast.
  final List<List<SketchStroke>> _undo = [];
  // True once the current erase drag has captured its pre-erase snapshot, so a
  // single drag-to-erase is one undo step.
  bool _erasing = false;
  // Anchor point for shape tools (line/rect/ellipse): set on pan-start, cleared
  // on pan-end. Null when a freehand pen or eraser is active.
  Offset? _shapeStart;

  double get _eraserRadius => math.max(_width * 1.5, 10);

  void _eraseAt(Offset o) {
    final before = _strokes;
    final after = eraseStrokesAt(before, o.dx, o.dy, _eraserRadius);
    if (after.length == before.length) return; // nothing under the pointer
    if (!_erasing) {
      _undo.add(before);
      _erasing = true;
    }
    setState(() => _strokes = after);
  }

  // Returns computed points for the active shape tool from [start] to [end],
  // in canvas coordinates. Rect = 5 closed corners; ellipse = 36-segment polyline.
  List<List<double>> _shapePoints(Offset start, Offset end) {
    final sx = start.dx, sy = start.dy, ex = end.dx, ey = end.dy;
    switch (_tool) {
      case _SketchTool.line:
        return [
          [sx, sy],
          [ex, ey]
        ];
      case _SketchTool.rect:
        return [
          [sx, sy],
          [ex, sy],
          [ex, ey],
          [sx, ey],
          [sx, sy],
        ];
      case _SketchTool.ellipse:
        final cx = (sx + ex) / 2, cy = (sy + ey) / 2;
        final rx = (ex - sx).abs() / 2, ry = (ey - sy).abs() / 2;
        const steps = 36;
        return [
          for (var i = 0; i <= steps; i++)
            [
              cx + rx * math.cos(2 * math.pi * i / steps),
              cy + ry * math.sin(2 * math.pi * i / steps),
            ],
        ];
      default:
        return [];
    }
  }

  void _save() {
    widget.onDone(SketchData(
      canvasWidth: _canvas.width,
      canvasHeight: _canvas.height,
      strokes: _strokes,
      backgroundBlobId: widget.backgroundBlobId,
      pdfBlobId: widget.pdfBlobId,
      pdfPage: widget.pdfPage,
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
            onPressed: _undo.isEmpty
                ? null
                : () => setState(() => _strokes = _undo.removeLast()),
          ),
          IconButton(
            key: const Key('sketch-clear'),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: () => setState(() {
              if (_strokes.isNotEmpty) _undo.add(_strokes);
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
          Expanded(child: _canvasArea(preview)),
          _toolbar(),
        ],
      ),
    );
  }

  /// The drawing surface. With a background image the surface is locked to the
  /// image's aspect ratio so strokes and image share one coordinate space and
  /// scale uniformly — without this the stretch-to-fill stroke scaling would
  /// drift from the BoxFit.contain image whenever container aspect ≠ canvas.
  Widget _canvasArea(SketchData preview) {
    final surface = LayoutBuilder(builder: (context, constraints) {
      _canvas = Size(constraints.maxWidth, constraints.maxHeight);
      return GestureDetector(
        key: const Key('sketch-canvas'),
        onPanStart: (d) {
          if (_tool == _SketchTool.eraser) {
            _erasing = false;
            _eraseAt(d.localPosition);
          } else if (_tool == _SketchTool.pen) {
            setState(() => _current = [_xy(d.localPosition)]);
          } else {
            setState(() {
              _shapeStart = d.localPosition;
              _current = [];
            });
          }
        },
        onPanUpdate: (d) {
          if (_tool == _SketchTool.eraser) {
            _eraseAt(d.localPosition);
          } else if (_tool == _SketchTool.pen) {
            setState(() => _current.add(_xy(d.localPosition)));
          } else if (_shapeStart != null) {
            setState(
                () => _current = _shapePoints(_shapeStart!, d.localPosition));
          }
        },
        onPanEnd: (_) {
          if (_tool == _SketchTool.eraser) {
            _erasing = false;
            return;
          }
          setState(() {
            if (_current.isNotEmpty) {
              _undo.add(_strokes);
              _strokes = [
                ..._strokes,
                SketchStroke(color: _color, width: _width, points: _current),
              ];
            }
            _current = [];
            _shapeStart = null;
          });
        },
        child: CustomPaint(
          painter: SketchPainter(preview, background: widget.background),
          size: Size.infinite,
        ),
      );
    });
    final bg = widget.background;
    if (bg == null) return surface;
    return Center(
      child: AspectRatio(aspectRatio: bg.width / bg.height, child: surface),
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
              const SizedBox(width: 4),
              IconButton(
                key: const Key('sketch-tool-pen'),
                icon: const Icon(Icons.edit),
                tooltip: 'Pen',
                isSelected: _tool == _SketchTool.pen,
                color: _tool == _SketchTool.pen ? Colors.blue : null,
                onPressed: () => setState(() => _tool = _SketchTool.pen),
              ),
              IconButton(
                key: const Key('sketch-tool-eraser'),
                icon: const Icon(Icons.auto_fix_normal),
                tooltip: 'Eraser',
                isSelected: _tool == _SketchTool.eraser,
                color: _tool == _SketchTool.eraser ? Colors.blue : null,
                onPressed: () => setState(() => _tool = _SketchTool.eraser),
              ),
              IconButton(
                key: const Key('sketch-tool-line'),
                icon: const Icon(Icons.remove),
                tooltip: 'Line',
                isSelected: _tool == _SketchTool.line,
                color: _tool == _SketchTool.line ? Colors.blue : null,
                onPressed: () => setState(() => _tool = _SketchTool.line),
              ),
              IconButton(
                key: const Key('sketch-tool-rect'),
                icon: const Icon(Icons.crop_square),
                tooltip: 'Rectangle',
                isSelected: _tool == _SketchTool.rect,
                color: _tool == _SketchTool.rect ? Colors.blue : null,
                onPressed: () => setState(() => _tool = _SketchTool.rect),
              ),
              IconButton(
                key: const Key('sketch-tool-ellipse'),
                icon: const Icon(Icons.radio_button_unchecked),
                tooltip: 'Ellipse',
                isSelected: _tool == _SketchTool.ellipse,
                color: _tool == _SketchTool.ellipse ? Colors.blue : null,
                onPressed: () => setState(() => _tool = _SketchTool.ellipse),
              ),
            ],
          ),
        ),
      );
}

/// Opens the editor full-screen; returns the drawing or null on cancel.
Future<SketchData?> showSketchEditor(
  BuildContext context, {
  SketchData? initial,
  ui.Image? background,
  String? backgroundBlobId,
  String? pdfBlobId,
  int? pdfPage,
}) {
  return Navigator.of(context).push<SketchData>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => SketchEditor(
      initial: initial,
      background: background,
      backgroundBlobId: backgroundBlobId,
      pdfBlobId: pdfBlobId,
      pdfPage: pdfPage,
      onDone: (d) => Navigator.of(context).pop(d),
    ),
  ));
}

/// Decodes raw image [bytes] into a [ui.Image] for use as an editor/painter
/// background. Returns null on null/empty input or a decode failure.
Future<ui.Image?> decodeSketchBackground(List<int>? bytes) async {
  if (bytes == null || bytes.isEmpty) return null;
  try {
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    try {
      final frame = await codec.getNextFrame();
      return frame.image; // caller owns the image and must dispose it
    } finally {
      codec.dispose(); // release the decoder's native resources
    }
  } catch (_) {
    return null; // unsupported/corrupt image → fall back to paper
  }
}
