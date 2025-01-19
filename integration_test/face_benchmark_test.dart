// integration_test/face_benchmark_test.dart

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import "package:flutter_driver/driver_extension.dart";
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_mlkit/services/face_benchmark_service.dart';
import 'package:prototipo_mlkit/utils/benchmark_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  enableFlutterDriverExtension();
  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('FaceBenchmarkService', () {
    late FaceBenchmarkService benchmarkService;
    // ignore: unused_local_variable
    late FirebaseStorage storage;

    setUp(() {
      benchmarkService = FaceBenchmarkService();
      storage = FirebaseStorage.instance;
    });

  tearDown(() async {
    await benchmarkService.dispose();
  });

  Future<void> uploadFileToFirebase(File file, String destinationPath) async {
    try {
      final storageRef = FirebaseStorage.instance.ref(destinationPath);
      final uploadTask = await storageRef.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      print('✅ Archivo subido exitosamente a Firebase Storage: $downloadUrl');
    } catch (e) {
      print('❌ Error al subir el archivo a Firebase Storage: $e');
      rethrow;
    }
  }

  test('Run benchmark and generate CSV', () async {
    const String annotationFilePath = 'assets/wider_face_val_bbx_gt.txt';

    // Ejecutar el benchmark
    final List<BenchmarkResult> results =
        await benchmarkService.runBenchmark(annotationFilePath);

    expect(results.isNotEmpty, true);
    print('✅ Se procesaron ${results.length} imágenes.');

    // Verificar que el archivo CSV se haya creado
    final String storagePath = await benchmarkService.getStoragePath();
    final Directory directory = Directory(storagePath);
    final List<FileSystemEntity> files = directory.listSync();

    final Iterable<File> csvFiles = files.whereType<File>().where((file) =>
        file.path.endsWith('.csv') &&
        file.path.contains('benchmark_results'));

    expect(csvFiles.isNotEmpty, true);
    print('✅ Archivo CSV generado: ${csvFiles.first.path}');

    // Subir el archivo a Firebase Storage
    final File csvFile = csvFiles.first;
    if (csvFile.existsSync()) {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String destinationPath = 'benchmark_results/benchmark_results_$timestamp.csv';

      await uploadFileToFirebase(csvFile, destinationPath);
    } else {
      print('❌ Archivo CSV no encontrado en la ruta: ${csvFile.path}');
    }
  }, timeout: const Timeout(Duration(seconds: 1800)));
});
}