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
