import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/benchmark_result.dart';

class FaceBenchmarkService {
  final List<BenchmarkResult> results = [];

  double averageIoU = 0.0;
  int totalTruePositives = 0;
  int totalFalsePositives = 0;
  int totalFalseNegatives = 0;

  final Stopwatch stopwatch = Stopwatch();
  int processedImages = 0;

  // Detector de Google ML Kit
  late final FaceDetector faceDetector;

  // Archivo CSV principal
  File? csvFile;

  FaceBenchmarkService() {
    faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: false,
        enableContours: false,
        minFaceSize: 0.05, // Ajustar si las caras son pequeñas
      ),
    );
  }

  // Liberar recursos
  Future<void> dispose() async {
    faceDetector.close();
  }

  /// Crea un [InputImage] a partir de un asset (sin rotación extra).
  Future<InputImage> prepareInputImage(String assetPath) async {
    try {
      print('📂 Cargando imagen desde assets: $assetPath');
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List();

      // Decodificar para verificar que no esté corrupta y obtener dimensiones
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw Exception('❌ Formato de imagen no soportado o imagen corrupta.');
      }

      final double originalWidth = decoded.width.toDouble();
      final double originalHeight = decoded.height.toDouble();

      print('📏 Dimensiones originales de la imagen:');
      print('- Ancho: ${originalWidth.toStringAsFixed(0)}px');
      print('- Alto: ${originalHeight.toStringAsFixed(0)}px');
      print(' - Relación de aspecto: '
          '${(originalWidth / originalHeight).toStringAsFixed(2)}');

      // Guarda la imagen en un archivo temporal
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/${assetPath.split('/').last}';
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(bytes);

      // Crear el InputImage
      print('📸 Creando InputImage desde archivo: ${tempFile.path}');
      final inputImage = InputImage.fromFile(tempFile);
      return inputImage;
    } catch (e) {
      print('❌ Error preparando InputImage: $e');
      rethrow;
    }
  }

  /// Directorio interno donde se guardan los resultados
  Future<String> _getResultsDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final resultsPath = '${directory.path}/BenchmarkResults';
    final resultsDir = Directory(resultsPath);
    if (!await resultsDir.exists()) {
      await resultsDir.create(recursive: true);
      print('📁 Creando directorio de resultados: $resultsPath');
    }
    return resultsPath;
  }

  /// Inicializar archivo CSV con cabecera (opcional si quieres uno único por ejecución)
  Future<File> initializeCSV() async {
    final resultsPath = await _getResultsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss_SSS').format(DateTime.now());
    final fileName = 'benchmark_results_$timestamp.csv';
    final file = File('$resultsPath/$fileName');

    // Escribir cabecera
    await file.writeAsString(
      'image_path,ground_truth,detected,iou,true_pos,false_pos,false_neg,'
      'precision,recall,f1_score,processing_time_ms\n',
    );
    print('📄 Archivo CSV creado: ${file.path}');
    return file;
  }

  /// Detección de rostros usando ML Kit
  Future<List<BoundingBox>> detectFaces(InputImage inputImage) async {
    print('🔍 Iniciando detección de caras...');
    try {
      final List<Face> faces = await faceDetector.processImage(inputImage);
      print('✅ Detección completada. Caras encontradas: ${faces.length}');
      return faces.map((face) {
        return BoundingBox(
          x: face.boundingBox.left,
          y: face.boundingBox.top,
          width: face.boundingBox.width,
          height: face.boundingBox.height,
        );
      }).toList();
    } catch (e) {
      print('❌ Error en detección facial: $e');
      return [];
    }
  }

  /// Calcular Intersection Over Union (IoU) entre dos cajas
  double calculateIoU(BoundingBox box1, BoundingBox box2) {
    final x1A = box1.x;
    final y1A = box1.y;
    final x2A = box1.x + box1.width;
    final y2A = box1.y + box1.height;

    final x1B = box2.x;
    final y1B = box2.y;
    final x2B = box2.x + box2.width;
    final y2B = box2.y + box2.height;

    final x1 = math.max(x1A, x1B);
    final y1 = math.max(y1A, y1B);
    final x2 = math.min(x2A, x2B);
    final y2 = math.min(y2A, y2B);

    final intersectionWidth = x2 - x1;
    final intersectionHeight = y2 - y1;
    if (intersectionWidth <= 0 || intersectionHeight <= 0) {
      return 0.0;
    }

    final intersectionArea = intersectionWidth * intersectionHeight;
    final areaA = box1.width * box1.height;
    final areaB = box2.width * box2.height;
    final unionArea = areaA + areaB - intersectionArea;

    return intersectionArea / unionArea;
  }

  /// Exportar resultados de UNA imagen al CSV global
  Future<void> exportResultsToCSV(BenchmarkResult result) async {
    try {
      // Si no existe csvFile, inicialízalo
      if (csvFile == null) {
        csvFile = await initializeCSV();
      }

      final file = csvFile!;
      final line = [
        result.imageName,
        result.groundTruth,
        result.detected,
        result.iou.toStringAsFixed(4),
        result.truePositives,
        result.falsePositives,
        result.falseNegatives,
        result.precision.toStringAsFixed(4),
        result.recall.toStringAsFixed(4),
        result.f1Score.toStringAsFixed(4),
        result.processingTime
      ].join(',');

      await file.writeAsString('$line\n', mode: FileMode.append);
      print('📝 Resultados exportados para la imagen: ${result.imageName}');
    } catch (e) {
      print('❌ Error exportando resultados: $e');
      rethrow;
    }
  }

  /// Exportar métricas globales a un archivo separado (opcional)
  Future<void> exportGlobalMetrics() async {
    try {
      final resultsPath = await _getResultsDirectory();
      final file = File('$resultsPath/benchmark_global_metrics.csv');

      final globalPrecision = totalTruePositives == 0
          ? 0.0
          : totalTruePositives / (totalTruePositives + totalFalsePositives);
      final globalRecall = totalTruePositives == 0
          ? 0.0
          : totalTruePositives / (totalTruePositives + totalFalseNegatives);
      final globalF1 = (globalPrecision + globalRecall) > 0
          ? 2 * (globalPrecision * globalRecall) /
              (globalPrecision + globalRecall)
          : 0.0;

      final data = [
        'Metric,Value',
        'Average IoU,${averageIoU.toStringAsFixed(4)}',
        'Global Precision,${globalPrecision.toStringAsFixed(4)}',
        'Global Recall,${globalRecall.toStringAsFixed(4)}',
        'Global F1 Score,${globalF1.toStringAsFixed(4)}',
        'Total Images,$processedImages'
      ].join('\n');

      await file.writeAsString('$data\n');
      print('✅ Métricas globales exportadas correctamente en: ${file.path}');
    } catch (e) {
      print('❌ Error exportando métricas globales: $e');
      rethrow;
    }
  }

  /// Corre el benchmark sobre las imágenes definidas en [annotationFilePath]
  Future<List<BenchmarkResult>> runBenchmark(String annotationFilePath) async {
    final List<BenchmarkResult> benchmarkResults = [];
    averageIoU = 0.0;
    totalTruePositives = 0;
    totalFalsePositives = 0;
    totalFalseNegatives = 0;
    processedImages = 0;

    try {
      print('📂 Cargando archivo de anotaciones: $annotationFilePath');
      final data = await rootBundle.loadString(annotationFilePath);
      final lines = data.split('\n');
      print('✅ Archivo de anotaciones cargado.');

      final totalImages =
          lines.where((line) => line.trim().endsWith('.jpg')).length;
      print('📊 Total de imágenes a procesar: $totalImages');

      // Recorre las líneas del archivo
      for (int i = 0; i < lines.length; i++) {
        final imageName = lines[i].trim();
        if (!imageName.endsWith('.jpg')) continue;

        // Siguiente línea: groundTruth
        if (i + 1 >= lines.length) {
          print('❌ Datos insuficientes para groundTruth en $imageName');
          continue;
        }

        int groundTruth = 0;
        try {
          groundTruth = int.parse(lines[i + 1].trim());
        } catch (e) {
          print('❌ Error parseando groundTruth en $imageName: $e');
          continue;
        }

        print('\n🖼️ Procesando imagen: $imageName [GT=$groundTruth]');

        try {
          stopwatch.reset();
          stopwatch.start();

          // Preparar InputImage
          final inputImage =
              await prepareInputImage('assets/images/$imageName');

          // Decodificar la imagen
          final imageFile = File(inputImage.filePath!);
          final decoded = img.decodeImage(await imageFile.readAsBytes());
          if (decoded == null) {
            print('❌ Error decodificando imagen $imageName');
            continue;
          }

          final originalWidth = decoded.width.toDouble();
          final originalHeight = decoded.height.toDouble();
          print('📏 Dimensiones originales de la imagen:');
          print('- Ancho: ${originalWidth.toStringAsFixed(1)}px');
          print('- Largo: ${originalHeight.toStringAsFixed(1)}px');

          // Leer las cajas ground truth
          final groundTruthBoxes = <BoundingBox>[];
          for (int j = 0; j < groundTruth; j++) {
            if (i + 2 + j >= lines.length) {
              print('❌ No hay suficientes líneas para las cajas de $imageName');
              break;
            }
            final coords = lines[i + 2 + j].trim().split(RegExp(r'\s+'));
            if (coords.length < 4) {
              print('❌ Coordenadas insuficientes en $imageName');
              continue;
            }
            try {
              groundTruthBoxes.add(
                BoundingBox(
                  x: double.parse(coords[0]),
                  y: double.parse(coords[1]),
                  width: double.parse(coords[2]),
                  height: double.parse(coords[3]),
                ),
              );
            } catch (boxError) {
              print('❌ Error parseando caja en $imageName: $boxError');
            }
          }

          // Detectar rostros con MLKit
          final detectedBoxes = await detectFaces(inputImage);

          // Asumimos que no hubo reescalado
          // Si lo hubiera, tendrías que multiplicar x,y,width,height
          // por un factor scaleX y scaleY
          final adjustedDetectedBoxes = detectedBoxes; // sin cambio

          double totalIoU = 0.0;
          int truePositives = 0;
          int falsePositives = 0;

          // Para cada caja detectada, buscar la ground truth con mayor IoU
          for (var detectedBox in adjustedDetectedBoxes) {
            double maxIoU = 0.0;
            BoundingBox? matchedGtBox;

            for (var gtBox in groundTruthBoxes) {
              final iou = calculateIoU(detectedBox, gtBox);
              if (iou > maxIoU) {
                maxIoU = iou;
                matchedGtBox = gtBox;
              }
            }

            if (maxIoU >= 0.5 && matchedGtBox != null) {
              truePositives++;
              totalIoU += maxIoU;
              // Removemos la GT para no duplicar
              groundTruthBoxes.remove(matchedGtBox);
            } else {
              falsePositives++;
            }
          }

          final falseNegatives = groundTruth - truePositives;
          final averageIoULocal =
              (truePositives > 0) ? totalIoU / truePositives : 0.0;

          // Métricas
          final precision = (truePositives + falsePositives) > 0
              ? truePositives / (truePositives + falsePositives)
              : 0.0;
          final recall = (truePositives + falseNegatives) > 0
              ? truePositives / (truePositives + falseNegatives)
              : 0.0;
          final f1Score = (precision + recall) > 0
              ? 2 * (precision * recall) / (precision + recall)
              : 0.0;

          final elapsedMs = stopwatch.elapsedMilliseconds;
          stopwatch.stop();

          // Crear objeto de resultados
          final result = BenchmarkResult(
            imageName: imageName,
            groundTruth: groundTruth,
            detected: detectedBoxes.length,
            iou: averageIoULocal,
            truePositives: truePositives,
            falsePositives: falsePositives,
            falseNegatives: falseNegatives,
            precision: precision,
            recall: recall,
            f1Score: f1Score,
            processingTime: elapsedMs,
          );

          // Guardar en CSV
          await exportResultsToCSV(result);

          // Acumular métricas globales
          averageIoU =
              (averageIoU * processedImages + averageIoULocal) /
              (processedImages + 1);
          totalTruePositives += truePositives;
          totalFalsePositives += falsePositives;
          totalFalseNegatives += falseNegatives;

          benchmarkResults.add(result);
          processedImages++;

          final progress = (processedImages / totalImages) * 100;
          print('📈 Progreso: ${progress.toStringAsFixed(1)}% '
              '($processedImages/$totalImages)');

        } catch (err) {
          stopwatch.stop();
          print('❌ Error procesando $imageName: $err');
        }

        // Avanzar el índice para saltar las líneas de bounding boxes
        i += groundTruth + 1;
      }

      // Exportar métricas globales
      await exportGlobalMetrics();

    } catch (e) {
      print('❌ Error crítico en el benchmark: $e');
    }

    print('🏁 Benchmark finalizado');
    return benchmarkResults;
  }
}

/// Clase auxiliar para representar una bounding box
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
