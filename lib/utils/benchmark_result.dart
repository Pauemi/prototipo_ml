// lib/models/benchmark_result.dart

class BenchmarkResult {
  final String imageName;
  final int groundTruth;
  final int detected;
  final double iou;
  final int truePositives;
  final int falsePositives;
  final int falseNegatives;
  final int trueNegatives;
  final double precision;
  final double recall;
  final double specificity;
  final double f1Score;
  final int processingTime;

  BenchmarkResult({
    required this.imageName,
    required this.groundTruth,
    required this.detected,
    required this.iou,
    required this.truePositives,
    required this.falsePositives,
    required this.falseNegatives,
    required this.trueNegatives,
    required this.precision,
    required this.recall,
    required this.specificity,
    required this.f1Score,
    required this.processingTime,
  });
}

class BoundingBox {
  final double x;
  final double y;
  final double width;
  final double height;

  BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}
