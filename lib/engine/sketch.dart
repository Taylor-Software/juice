import 'dart:math' as math;

/// A single freehand stroke: an ARGB color, a width, and its points.
class SketchStroke {
  const SketchStroke(
      {required this.color, required this.width, required this.points});
  final int color;
  final double width;
  final List<List<double>> points; // [[x,y], ...]

  Map<String, dynamic> toJson() => {
        'c': color,
        'w': width,
        'p': points,
      };

  factory SketchStroke.fromJson(Map<String, dynamic> j) => SketchStroke(
        color: (j['c'] as num?)?.toInt() ?? 0xFF000000,
        width: (j['w'] as num?)?.toDouble() ?? 3,
        points: ((j['p'] as List?) ?? const <dynamic>[])
            .whereType<List<dynamic>>()
            .map((pt) => pt.whereType<num>().map((n) => n.toDouble()).toList())
            .where((pt) => pt.length == 2)
            .toList(),
      );
}

/// A vector sketch drawn at a known logical canvas size; round-trips via JSON.
class SketchData {
  const SketchData({
    required this.canvasWidth,
    required this.canvasHeight,
    this.strokes = const [],
  });
  final double canvasWidth;
  final double canvasHeight;
  final List<SketchStroke> strokes;

  bool get isEmpty => strokes.isEmpty;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'w': canvasWidth,
        'h': canvasHeight,
        'strokes': strokes.map((s) => s.toJson()).toList(),
      };

  factory SketchData.fromJson(Map<String, dynamic> j) => SketchData(
        canvasWidth: (j['w'] as num?)?.toDouble() ?? 1,
        canvasHeight: (j['h'] as num?)?.toDouble() ?? 1,
        strokes: (j['strokes'] is List
                ? (j['strokes'] as List<dynamic>)
                : const <dynamic>[])
            .whereType<Map<dynamic, dynamic>>()
            .map((m) => SketchStroke.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );
}

/// Minimum distance from `(x,y)` to the segment `a`–`b`.
double _distanceToSegment(double px, double py, double ax, double ay, double bx,
    double by) {
  final dx = bx - ax;
  final dy = by - ay;
  final len2 = dx * dx + dy * dy;
  if (len2 == 0) {
    // Degenerate segment: distance to the point.
    return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
  }
  var t = ((px - ax) * dx + (py - ay) * dy) / len2;
  t = t.clamp(0.0, 1.0);
  final cx = ax + t * dx;
  final cy = ay + t * dy;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}

/// Minimum distance from `(x,y)` to a stroke's polyline. A single-point stroke
/// measures to that point; an empty stroke is unreachable ([double.infinity]).
double distanceToStroke(SketchStroke s, double x, double y) {
  final pts = s.points;
  if (pts.isEmpty) return double.infinity;
  if (pts.length == 1) {
    final ex = x - pts[0][0];
    final ey = y - pts[0][1];
    return math.sqrt(ex * ex + ey * ey);
  }
  var min = double.infinity;
  for (var i = 0; i < pts.length - 1; i++) {
    final d = _distanceToSegment(
        x, y, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1]);
    if (d < min) min = d;
  }
  return min;
}

/// Returns [strokes] with every stroke the eraser at `(x,y)` touches removed.
/// A stroke is touched when the pointer comes within [radius] of it, accounting
/// for half the stroke's own width. Order is preserved; the input is not mutated.
List<SketchStroke> eraseStrokesAt(
        List<SketchStroke> strokes, double x, double y, double radius) =>
    [
      for (final s in strokes)
        if (distanceToStroke(s, x, y) > radius + s.width / 2) s,
    ];
