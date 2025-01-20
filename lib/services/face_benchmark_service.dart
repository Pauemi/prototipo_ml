// lib/services/face_benchmark_service.dart

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
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
  int totalTrueNegatives = 0;
  final Stopwatch stopwatch = Stopwatch();

  // Instancia única de FaceDetector
  late final FaceDetector faceDetector;

  // Variable para almacenar el archivo CSV
  File? csvFile;

  FaceBenchmarkService() {
    faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: false,
        enableContours: false,
        minFaceSize: 0.05, // Reducir si las caras son pequeñas
      ),
    );
  }

  Future<void> dispose() async {
    faceDetector.close();
  }

/// Sube el archivo CSV a Firebase Storage y retorna la URL de descarga.
  Future<String> uploadCSV(File csvFile) async {
    try {
      final storageRef = FirebaseStorage.instance.ref();
      final csvRef = storageRef.child('benchmark_results/${csvFile.uri.pathSegments.last}');
      final uploadTask = csvRef.putFile(csvFile);
      final snapshot = await uploadTask.whenComplete(() {});
      final downloadURL = await snapshot.ref.getDownloadURL();
      print('✅ CSV subido a Firebase Storage: $downloadURL');
      return downloadURL;
       // Verificar que la URL no esté vacía

    } catch (e) {
      print('❌ Error al subir el CSV: $e');
      return '';
    }
  }

  // Preparar InputImage y obtener dimensiones originales
  Future<InputImage> prepareInputImage(String assetPath) async {
    try {
      print('📂 Cargando imagen desde assets: $assetPath');
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List();

      // Verificar si la imagen está corrupta o tiene un formato no soportado
      final img.Image? originalImage = img.decodeImage(bytes);
      if (originalImage == null) {
        throw Exception('❌ Formato de imagen no soportado o imagen corrupta.');
      }
      final double originalWidth = originalImage.width.toDouble();
      final double originalHeight = originalImage.height.toDouble();
      print('📏 Dimensiones originales de la imagen:');
      print('- Ancho: ${originalWidth.toStringAsFixed(0)}px');
      print('- Alto: ${originalHeight.toStringAsFixed(0)}px');
      print(' - Relación de aspecto: ${(originalWidth / originalHeight).toStringAsFixed(2)}');

      // Guarda la imagen en un archivo temporal
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/${assetPath.split('/').last}';
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(bytes);

      

      print('📸 Creando InputImage desde archivo rotado: ${tempFile.path}');
      final inputImage = InputImage.fromFile(tempFile);

      return inputImage;
    } catch (e) {
      print('❌ Error preparando InputImage: $e');
      rethrow;
    }
  }

//Ruta de almacenamiento de resultados CSV
  Future<String> getStoragePath() async {
    final directory = await getApplicationDocumentsDirectory();
    final storagePath = '${directory.path}/BenchmarkResults';
    final storageDir = Directory(storagePath);
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
      print('📁 Creando directorio de almacenamiento: $storagePath');
    }
    return storagePath;
  }

  //Detección de caras con Google ML Kit
  Future<List<BoundingBox>> detectFaces(InputImage inputImage) async {
    print('🔍 Iniciando detección de caras...');
    try {
      final List<Face> faces = await faceDetector.processImage(inputImage);
      print('✅ Detección completada. Caras encontradas: ${faces.length}');
      return faces
          .map((face) => BoundingBox(
                x: face.boundingBox.left,
                y: face.boundingBox.top,
                width: face.boundingBox.width,
                height: face.boundingBox.height,
              ))
          .toList();
    } catch (e) {
      print('❌ Error en detección facial: $e');
      return [];
    }
  }

  double calculateIoU(BoundingBox box1, BoundingBox box2) {
    double x1A = box1.x;
    double y1A = box1.y;
    double x2A = box1.x + box1.width;
    double y2A = box1.y + box1.height;

    double x1B = box2.x;
    double y1B = box2.y;
    double x2B = box2.x + box2.width;
    double y2B = box2.y + box2.height;

    double x1 = math.max(x1A, x1B);
    double y1 = math.max(y1A, y1B);
    double x2 = math.min(x2A, x2B);
    double y2 = math.min(y2A, y2B);

    double intersectionWidth = x2 - x1;
    double intersectionHeight = y2 - y1;

    if (intersectionWidth <= 0 || intersectionHeight <= 0) {
      return 0.0;
    }

    double intersectionArea = intersectionWidth * intersectionHeight;
    double areaA = box1.width * box1.height;
    double areaB = box2.width * box2.height;
    double unionArea = areaA + areaB - intersectionArea;

    return intersectionArea / unionArea;
  }

//Inicialización del archivo CSV
  Future<File> initializeCSV() async {
    final storagePath = await getStoragePath();

    final timestamp = DateFormat('yyyyMMdd_HHmmss_SSS').format(DateTime.now());
    final fileName = 'benchmark_results_$timestamp.csv';
    final file = File('$storagePath/$fileName');

    // Crear archivo con headers
    await file.writeAsString(
        'image_path,ground_truth,detected,iou,true_pos,false_pos,false_neg,true_neg,precision,recall,specificity,f1_score,processing_time_ms\n');
    print('📄 Creando archivo CSV: ${file.path}');
    return file;
  }

//Exportación de resultados a CSV
  Future<void> exportResultsToCSV(BenchmarkResult result) async {
    if (csvFile == null) {
      print('❌ Archivo CSV no inicializado.');
      return;
    }

    // Agregar nueva línea de resultados
    final line = '${result.imageName},'
        '${result.groundTruth},'
        '${result.detected},'
        '${result.iou.toStringAsFixed(4)},'
        '${result.truePositives},'
        '${result.falsePositives},'
        '${result.falseNegatives},'
        '${result.trueNegatives},'
        '${result.precision.toStringAsFixed(4)},'
        '${result.recall.toStringAsFixed(4)},'
        '${result.specificity.toStringAsFixed(4)},'
        '${result.f1Score.toStringAsFixed(4)},'
        '${result.processingTime}\n';

    await csvFile!.writeAsString(line, mode: FileMode.append);

    // Agregar debug print
    print('📁 Resultados agregados al archivo CSV: ${csvFile!.path}');
  }

  /// Ejecuta el benchmark procesando cada imagen, detectando caras, calculando métricas y guardando los resultados en el CSV.
  /// @param annotationFilePath Ruta al archivo de anotaciones que contiene las rutas de las imágenes y las cajas de verdad de terreno.
  Future<List<BenchmarkResult>> runBenchmark(String annotationFilePath) async {
    final List<BenchmarkResult> benchmarkResults = [];
    averageIoU = 0.0;
    totalTruePositives = 0;
    totalFalsePositives = 0;
    totalFalseNegatives = 0;
    totalTrueNegatives = 0;

    try {
      print('📂 Cargando archivo de anotaciones: $annotationFilePath');
      final String data = await rootBundle.loadString(annotationFilePath);
      final List<String> lines = data.split('\n');
      print('✅ Archivo de anotaciones cargado exitosamente');

      // Contar el total de imágenes a procesar
      int totalImages =
          lines.where((line) => line.trim().endsWith('.jpg')).length;
      print('📊 Total de imágenes a procesar: $totalImages');

      // Inicializar archivo CSV
      csvFile = await initializeCSV();

      int processedImages = 0;

      for (int i = 0; i < lines.length; i++) {
        final String imageName = lines[i].trim();
        if (!imageName.endsWith('.jpg')) continue;

        print('🖼️ Procesando imagen: $imageName');

        // Verificar que haya suficientes líneas para groundTruth y bounding boxes
        if (i + 1 >= lines.length) {
          print(
              '❌ Datos insuficientes para groundTruth de la imagen $imageName. Saltando esta imagen.');
          continue;
        }

        final int groundTruth;
        try {
          groundTruth = int.parse(lines[i + 1].trim());
        } catch (e) {
          print(
              '❌ Error al parsear groundTruth para la imagen $imageName: $e. Saltando esta imagen.');
          continue;
        }

        print('📝 Ground Truth faces: $groundTruth');

        try {
          print('🔍 Iniciando detección de caras...');
          stopwatch.reset();
          stopwatch.start();

          // Obtener InputImage y dimensiones originales
          final InputImage inputImage = await prepareInputImage('assets/images/$imageName');
          final File imageFile = File(inputImage.filePath!);
          final img.Image? originalImage = img.decodeImage(await imageFile.readAsBytes());
          final double originalWidth = originalImage!.width.toDouble();
          final double originalHeight = originalImage.height.toDouble();

          print('📏 Dimensiones originales de la imagen:');
          print('- Ancho: ${originalWidth.toStringAsFixed(0)}px');
          print('- Alto: ${originalHeight.toStringAsFixed(0)}px');
          print(' - Relación de aspecto: ${(originalWidth / originalHeight).toStringAsFixed(2)}');

          final List<BoundingBox> groundTruthBoxes = [];
          for (int j = 0; j < groundTruth; j++) {
            if (i + 2 + j >= lines.length) {
              print(
                  '❌ Datos insuficientes para las cajas de la imagen $imageName. Saltando esta caja.');
              continue;
            }
            final List<String> coords =
                lines[i + 2 + j].trim().split(RegExp(r'\s+'));
            if (coords.length < 4) {
              print(
                  '❌ Datos insuficientes para las coordenadas de la caja en la imagen $imageName. Saltando esta caja.');
              continue;
            }
            try {
              groundTruthBoxes.add(BoundingBox(
                x: double.parse(coords[0]),
                y: double.parse(coords[1]),
                width: double.parse(coords[2]),
                height: double.parse(coords[3]),
              ));
            } catch (e) {
              print(
                  '❌ Error al parsear coordenadas para la caja en la imagen $imageName: $e. Saltando esta caja.');
              continue;
            }
          }

          final List<BoundingBox> detectedBoxes = await detectFaces(inputImage);

          // Asumimos que no hay redimensionamiento, por lo que scaleX y scaleY son 1.0
          double scaleX = 1.0;
          double scaleY = 1.0;

          // Ajustar las Bounding Boxes detectadas si hay escalado
          List<BoundingBox> adjustedDetectedBoxes = detectedBoxes
              .map((box) => BoundingBox(
                    x: box.x * scaleX,
                    y: box.y * scaleY,
                    width: box.width * scaleX,
                    height: box.height * scaleY,
                  ))
              .toList();

          double totalIoU = 0.0;
          int truePositives = 0;
          int falsePositives = 0;

          // Comparar cada caja detectada con las cajas ground truth
          for (var detectedBox in adjustedDetectedBoxes) {
            double maxIoU = 0.0;
            BoundingBox? matchedGtBox;

            for (var groundTruthBox in groundTruthBoxes) {
              final iou = calculateIoU(detectedBox, groundTruthBox);
              if (iou > maxIoU) {
                maxIoU = iou;
                matchedGtBox = groundTruthBox;
              }
            }

            if (maxIoU >= 0.5 && matchedGtBox != null) {
              truePositives++;
              totalIoU += maxIoU;
              // Remover la caja groundTruthBox para evitar múltiples asignaciones
              groundTruthBoxes.remove(matchedGtBox);
            } else {
              falsePositives++;
            }
          }

          final falseNegatives = groundTruth - truePositives;
//Calculo de True Negatives
          int trueNegatives = 0;
          if (groundTruth == 0) {
            if (detectedBoxes.isEmpty) {
              trueNegatives += 1;
              print('✅ Verdadero Negativo para la imagen $imageName');
            } else {
              // Cualquier detección en imágenes sin rostros es un FP
              falsePositives += detectedBoxes.length;
              print(
                  '⚠️ Falsos Positivos detectados en imagen sin rostros: $imageName');
            }
          }
          final averageIoULocal =
              truePositives > 0 ? totalIoU / truePositives : 0.0;

          // Calcular métricas adicionales
          final double precision = (truePositives + falsePositives) > 0
              ? truePositives / (truePositives + falsePositives)
              : 0.0;
          final double recall = (truePositives + falseNegatives) > 0
              ? truePositives / (truePositives + falseNegatives)
              : 0.0;
          final double f1Score = (precision + recall) > 0
              ? 2 * (precision * recall) / (precision + recall)
              : 0.0;

          final double specificity = (trueNegatives + falsePositives) > 0
              ? trueNegatives / (trueNegatives + falsePositives)
              : 0.0;

          final benchmarkResult = BenchmarkResult(
            imageName: imageName,
            groundTruth: groundTruth,
            detected: detectedBoxes.length,
            iou: averageIoULocal,
            truePositives: truePositives,
            falsePositives: falsePositives,
            falseNegatives: falseNegatives,
            trueNegatives: trueNegatives,
            precision: precision,
            recall: recall,
            specificity: specificity,
            f1Score: f1Score,
            processingTime: stopwatch.elapsedMilliseconds,
          );

          // Guardar resultados en CSV
          await exportResultsToCSV(benchmarkResult);

          // Actualizar métricas globales
          averageIoU = (averageIoU * processedImages + averageIoULocal) /
              (processedImages + 1);
          totalTruePositives += truePositives;
          totalFalsePositives += falsePositives;
          totalFalseNegatives += falseNegatives;
          totalTrueNegatives += trueNegatives;

          benchmarkResults.add(benchmarkResult);

          processedImages++;
          print(
              '📈 Progreso: ${(processedImages / totalImages * 100).toStringAsFixed(1)}%');
                
        } catch (e) {
          print('❌ Error procesando $imageName: $e');
        } finally {
          stopwatch.stop();
        }

        // Saltar las líneas de bounding boxes ya procesadas
        i += groundTruth + 1;
      }
    } catch (e) {
      print('❌ Error crítico en el benchmark: $e');
    }

    print('🏁 Benchmark finalizado');
    return benchmarkResults;
  }
}
