// lib/widgets/face_benchmark.dart

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:prototipo_mlkit/utils/permission.dart';

import '../services/face_benchmark_service.dart';
import '../utils/benchmark_result.dart';

class FaceBenchmark extends StatefulWidget {
  const FaceBenchmark({super.key});

  @override
  State<FaceBenchmark> createState() => _FaceBenchmarkState();
}

class _FaceBenchmarkState extends State<FaceBenchmark> {
  final FaceBenchmarkService benchmarkService = FaceBenchmarkService();
  final List<BenchmarkResult> results = [];
  bool isRunning = false;
  double progress = 0.0;
  double averageIoU = 0.0;
  int totalTruePositives = 0;
  int totalFalsePositives = 0;
  int totalFalseNegatives = 0;

  Future<bool> requestStoragePermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
      if (status.isGranted) {
        print('✅ Permiso de almacenamiento concedido.');
        return true;
      } else {
        print('❌ Permiso de almacenamiento denegado.');
        return false;
      }
    }
    return true;
  }
  
  @override
  void dispose() {
    benchmarkService.dispose();
    super.dispose();
  }

  Future<void> _runBenchmark() async {
     // Verificar permisos antes de proceder
    bool hasPermission = await ensureStoragePermission();
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se requieren permisos de almacenamiento para guardar el archivo CSV.'),
        ),
      );
      return;
    }

    print('🚀 Iniciando benchmark...');
    setState(() {
      isRunning = true;
      results.clear();
      averageIoU = 0.0;
      totalTruePositives = 0;
      totalFalsePositives = 0;
      totalFalseNegatives = 0;
      progress = 0.0;
    });

    try {
      const String annotationFilePath = 'assets/wider_face_val_bbx_gt.txt';
      final List<BenchmarkResult> benchmarkResults =
          await benchmarkService.runBenchmark(annotationFilePath);

      setState(() {
        results.addAll(benchmarkResults);

        // Actualizar métricas globales
        for (var result in benchmarkResults) {
          averageIoU = (averageIoU * totalTruePositives + result.iou) /
              (totalTruePositives + 1);
          totalTruePositives += result.truePositives;
          totalFalsePositives += result.falsePositives;
          totalFalseNegatives += result.falseNegatives;
        }

        progress = 1.0;
      });
    } catch (e) {
      print('❌ Error durante el benchmark: $e');
    } finally {
      setState(() {
        isRunning = false;
        progress = 0.0;
      });
      print('🏁 Benchmark finalizado');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WiderFace Benchmark')),
      body: Column(
        children: [
          if (isRunning) LinearProgressIndicator(value: progress),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Text('IoU Promedio: ${averageIoU.toStringAsFixed(3)}'),
                Text('Verdaderos Positivos: $totalTruePositives'),
                Text('Falsos Positivos: $totalFalsePositives'),
                Text('Falsos Negativos: $totalFalseNegatives'),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: isRunning ? null : _runBenchmark,
            child: Text(isRunning ? 'Ejecutando...' : 'Iniciar Benchmark'),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final result = results[index];
                return ListTile(
                  title: Text(result.imageName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Ground Truth: ${result.groundTruth} | Detectado: ${result.detected}'),
                      Text('IoU: ${result.iou.toStringAsFixed(3)}'),
                      Text(
                          'TP: ${result.truePositives} | FP: ${result.falsePositives} | FN: ${result.falseNegatives}'),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
