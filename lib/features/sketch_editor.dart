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
enum _SketchTool { pen, eraser, line, rect, ellipse, text, pan }

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
    for (final t in data.texts) {
      final tp = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(color: Color(t.color), fontSize: t.size * sy),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(t.x * sx, t.y * sy));
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
  late List<SketchText> _texts = [...?widget.initial?.texts];
  List<List<double>> _current = [];
  int _color = _palette.first;
  double _width = 3;
  Size _canvas = const Size(1, 1);
  _SketchTool _tool = _SketchTool.pen;
  // Pan/zoom viewport transform (view-only — never saved into the sketch).
  final TransformationController _tc = TransformationController();
  // Undo history: snapshots of (strokes, texts) before each mutation, so every
  // op (draw, shape, erase, clear, text add/edit) is one undo step.
  final List<({List<SketchStroke> strokes, List<SketchText> texts})> _undo = [];

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _snapshot() => _undo.add((strokes: _strokes, texts: _texts));

  // True once the current erase drag has captured its pre-erase snapshot, so a
  // single drag-to-erase is one undo step.
  bool _erasing = false;
  // Anchor point for shape tools (line/rect/ellipse): set on pan-start, cleared
  // on pan-end. Null when a freehand pen or eraser is active.
  Offset? _shapeStart;

  double get _eraserRadius => math.max(_width * 1.5, 10);
  static const _textHitRadius = 22.0;

  void _eraseAt(Offset o) {
    final beforeStrokes = _strokes;
    final beforeTexts = _texts;
    final afterStrokes =
        eraseStrokesAt(beforeStrokes, o.dx, o.dy, _eraserRadius);
    final afterTexts = eraseTextsAt(beforeTexts, o.dx, o.dy, _eraserRadius);
    if (afterStrokes.length == beforeStrokes.length &&
        afterTexts.length == beforeTexts.length) {
      return; // nothing under the pointer
    }
    if (!_erasing) {
      _snapshot(); // _strokes/_texts still hold the pre-erase values here
      _erasing = true;
    }
    setState(() {
      _strokes = afterStrokes;
      _texts = afterTexts;
    });
  }

  /// Text-tool tap: edit the label under the tap if one is near, else place a
  /// new one. Cancel (null) leaves everything unchanged.
  Future<void> _handleTextTap(Offset o) async {
    SketchText? hit;
    for (final t in _texts) {
      if (distanceToText(t, o.dx, o.dy) <= _textHitRadius) {
        hit = t;
        break;
      }
    }
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextLabelDialog(initial: hit?.text ?? ''),
    );
    if (!mounted || result == null) return; // cancelled / disposed
    final value = result.trim();
    setState(() {
      if (hit != null) {
        _snapshot();
        _texts = [
          for (final t in _texts)
            if (!identical(t, hit))
              t
            else if (value.isNotEmpty)
              SketchText(
                  text: value, x: t.x, y: t.y, color: t.color, size: t.size),
        ];
      } else if (value.isNotEmpty) {
        _snapshot();
        _texts = [
          ..._texts,
          SketchText(text: value, x: o.dx, y: o.dy, color: _color),
        ];
      }
    });
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
      texts: _texts,
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
      texts: _texts,
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
            key: const Key('sketch-zoom-reset'),
            icon: const Icon(Icons.zoom_out_map),
            tooltip: 'Reset zoom',
            onPressed: () => setState(() => _tc.value = Matrix4.identity()),
          ),
          IconButton(
            key: const Key('sketch-undo'),
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: _undo.isEmpty
                ? null
                : () => setState(() {
                      final snap = _undo.removeLast();
                      _strokes = snap.strokes;
                      _texts = snap.texts;
                    }),
          ),
          IconButton(
            key: const Key('sketch-clear'),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: () => setState(() {
              if (_strokes.isNotEmpty || _texts.isNotEmpty) _snapshot();
              _strokes = [];
              _texts = [];
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
      final isPan = _tool == _SketchTool.pan;
      final canDraw = _tool != _SketchTool.text && !isPan;
      // The GestureDetector is the outer widget so it wins the gesture arena
      // against InteractiveViewer's internal recognizers. In pan mode its
      // callbacks are nulled out so the InteractiveViewer below handles panning.
      return GestureDetector(
        key: const Key('sketch-canvas'),
        onTapUp: _tool == _SketchTool.text
            ? (d) => _handleTextTap(_scene(d.localPosition))
            : null,
        onPanStart: !canDraw
            ? null
            : (d) {
                final p = _scene(d.localPosition);
                if (_tool == _SketchTool.eraser) {
                  _erasing = false;
                  _eraseAt(p);
                } else if (_tool == _SketchTool.pen) {
                  setState(() => _current = [_xy(p)]);
                } else {
                  setState(() {
                    _shapeStart = p;
                    _current = [];
                  });
                }
              },
        onPanUpdate: !canDraw
            ? null
            : (d) {
                final p = _scene(d.localPosition);
                if (_tool == _SketchTool.eraser) {
                  _eraseAt(p);
                } else if (_tool == _SketchTool.pen) {
                  setState(() => _current.add(_xy(p)));
                } else if (_shapeStart != null) {
                  setState(() => _current = _shapePoints(_shapeStart!, p));
                }
              },
        onPanEnd: !canDraw
            ? null
            : (_) {
                if (_tool == _SketchTool.eraser) {
                  _erasing = false;
                  return;
                }
                setState(() {
                  if (_current.isNotEmpty) {
                    _snapshot();
                    _strokes = [
                      ..._strokes,
                      SketchStroke(
                          color: _color, width: _width, points: _current),
                    ];
                  }
                  _current = [];
                  _shapeStart = null;
                });
              },
        child: AbsorbPointer(
          // In drawing/text mode the InteractiveViewer must not participate in
          // hit-testing, otherwise its internal recognizers compete with the
          // outer GestureDetector and win. In pan mode we let it through so its
          // pan/scale recognizers handle the interaction directly.
          absorbing: !isPan,
          child: InteractiveViewer(
            transformationController: _tc,
            panEnabled: isPan,
            scaleEnabled: isPan,
            // minScale 1 = never shrink below fit (the canvas already fits the
            // viewport); zoom in to pan within the canvas bounds. Keep the
            // default constrained:true — the child is `Size.infinite`, so
            // constrained:false would give it an unbounded layout.
            minScale: 1.0,
            maxScale: 6.0,
            child: CustomPaint(
              painter: SketchPainter(preview, background: widget.background),
              size: Size.infinite,
            ),
          ),
        ),
      );
    });
    final bg = widget.background;
    if (bg == null) return surface;
    return Center(
      child: AspectRatio(aspectRatio: bg.width / bg.height, child: surface),
    );
  }

  /// Viewport point → canvas (scene) point, inverting the zoom/pan transform.
  /// At scale 1 / no pan this is the identity, so drawing is unchanged.
  Offset _scene(Offset viewport) => _tc.toScene(viewport);

  List<double> _xy(Offset o) => [o.dx, o.dy];

  Widget _toolbar() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
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
                const SizedBox(width: 16),
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
                IconButton(
                  key: const Key('sketch-tool-text'),
                  icon: const Icon(Icons.title),
                  tooltip: 'Text',
                  isSelected: _tool == _SketchTool.text,
                  color: _tool == _SketchTool.text ? Colors.blue : null,
                  onPressed: () => setState(() => _tool = _SketchTool.text),
                ),
                IconButton(
                  key: const Key('sketch-tool-pan'),
                  icon: const Icon(Icons.pan_tool_outlined),
                  tooltip: 'Pan & zoom',
                  isSelected: _tool == _SketchTool.pan,
                  color: _tool == _SketchTool.pan ? Colors.blue : null,
                  onPressed: () => setState(() => _tool = _SketchTool.pan),
                ),
              ],
            ),
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

/// Disposes a sketch-editor background image AFTER the editor's pop transition
/// has finished painting it. Disposing inline (right after [showSketchEditor]
/// resolves) races the exit animation — the painter keeps drawing the image for
/// a few frames and would paint a freed one ("Cannot paint an image that is
/// disposed"). One second is well past the ~300ms transition. No-op for null.
void disposeSketchBackgroundLater(ui.Image? bg) {
  if (bg != null) Future.delayed(const Duration(seconds: 1), bg.dispose);
}

/// A tiny dialog that prompts for a text-label string. Owns its
/// [TextEditingController] so it is disposed after the dialog's exit transition
/// (disposing it inline in the caller would tear it down mid-animation).
/// Pops the entered text on OK / submit, or null on Cancel.
class _TextLabelDialog extends StatefulWidget {
  const _TextLabelDialog({required this.initial});
  final String initial;

  @override
  State<_TextLabelDialog> createState() => _TextLabelDialogState();
}

class _TextLabelDialogState extends State<_TextLabelDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('sketch-text-dialog'),
        title: const Text('Text label'),
        content: TextField(
          key: const Key('sketch-text-field'),
          controller: _controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(_controller.text),
              child: const Text('OK')),
        ],
      );
}
