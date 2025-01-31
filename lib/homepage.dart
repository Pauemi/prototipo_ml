// lib/homepage.dart
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ImagePicker _picker = ImagePicker();
  late FaceDetector _faceDetector;
  File? _image;
  List<Face>? _faces;
  bool _isProcessing = false;
  double? _imageWidth;
  double? _imageHeight;

  @override
  void initState() {
    super.initState();
    final options = FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: false,
      enableContours: true,
    );
    _faceDetector = FaceDetector(options: options);
  }

  @override
  void dispose() {
    _faceDetector.close();
    super.dispose();
  }

  Future<bool> requestStoragePermission() async {
  print('📁 Solicitando permisos de almacenamiento...');
  if (Platform.isAndroid) {
    int sdkInt = await _getAndroidSdkInt();
    print('📱 Versión SDK de Android: $sdkInt');

    if (sdkInt >= 33) {
      // Android 13+ permisos específicos
      print('🔍 Solicitando permisos específicos para Android 13+');
      Map<Permission, PermissionStatus> statuses = await [
        Permission.photos, // Para imágenes
        Permission.videos, // Para videos
        Permission.audio,  // Para audio
      ].request();

      // Registrar estados de permisos
      statuses.forEach((permission, status) {
        print('🔸 Permiso $permission: $status');
      });

      bool allGranted = statuses.values.every((status) => status.isGranted);

      if (!allGranted) {
        print('❌ No se concedieron todos los permisos. Abriendo configuración.');
        await openAppSettings();
      }
      return allGranted;
    } else {
      // Android < 13 permisos tradicionales
      print('Solicitando permisos tradicionales para Android < 13');
      PermissionStatus status = await Permission.storage.request();
      print('Estado del permiso storage: $status');

      if (status.isGranted) {
        return true;
      } else if (status.isPermanentlyDenied) {
        print('Permiso denegado permanentemente. Abriendo configuración.');
        await openAppSettings();
        return false;
      } else {
        return false;
      }
    }
  } else if (Platform.isIOS) {
    // iOS permisos para fotos
    print('Solicitando permisos para fotos en iOS');
    PermissionStatus status = await Permission.photos.request();
    print('Estado del permiso photos: $status');

    if (status.isGranted) {
      return true;
    } else if (status.isPermanentlyDenied) {
      print('Permiso denegado permanentemente. Abriendo configuración.');
      await openAppSettings();
      return false;
    } else {
      return false;
    }
  }

  // Si no es Android ni iOS
  return false;
}

Future<int> _getAndroidSdkInt() async {
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
  return androidInfo.version.sdkInt;
}

  Future<bool> _requestCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
      if (status.isGranted) {
        print('✅ Permiso de cámara concedido.');
        return true;
      } else {
        print('❌ Permiso de cámara denegado.');
        return false;
      }
    }
    return true;
  }
  
  Future<File> _prepareImage(File imageFile) async {
    try {
      print('📂 Cargando imagen para rotación: ${imageFile.path}');
      
      // Corrige la orientación usando EXIF
      final rotatedFile = await FlutterExifRotation.rotateImage(path: imageFile.path);
      
      print('📸 Imagen rotada: ${rotatedFile.path}');
      return rotatedFile;
    } catch (e) {
      print('❌ Error al rotar la imagen: $e');
      return imageFile; // Retorna la imagen original si falla la rotación
    }
  }

  Future<void> _pickImageFromGallery() async {
  if (!await requestStoragePermission()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Se necesita acceso a la galería')),
    );
    return;
  }

  print('📸 Iniciando selección de imagen desde galería');
  final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
  if (pickedFile != null) {
    print('✅ Imagen seleccionada desde galería: ${pickedFile.path}');
    setState(() {
      _image = File(pickedFile.path);
      _isProcessing = true;
    });
    await _getImageDimensions();
    await _detectFaces();
  } else {
    print('❌ No se seleccionó ninguna imagen de la galería');
  }
}


  Future<void> _pickImageFromCamera() async {
    if (!await _requestCameraPermission()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Se necesita acceso a la cámara')),
      );
      return;
    }

    print('📸 Iniciando captura de imagen desde cámara');
    final pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      print('✅ Imagen capturada desde cámara: ${pickedFile.path}');
      setState(() {
        _image = File(pickedFile.path);
        _isProcessing = true;
      });
      await _getImageDimensions();
      await _detectFaces();
    } else {
      print('❌ No se capturó ninguna imagen de la cámara');
    }
  }

  Future<void> _getImageDimensions() async {
    if (_image == null) return;
    print('📏 Obteniendo dimensiones de la imagen...');
    final decodedImage = await decodeImageFromList(_image!.readAsBytesSync());
    setState(() {
      _imageWidth = decodedImage.width.toDouble();
      _imageHeight = decodedImage.height.toDouble();
    });
    print('✅ Dimensiones obtenidas: ${_imageWidth}x$_imageHeight');
  }

  Future<void> _detectFaces() async {
    if (_image == null) return;
    print('🔍 Iniciando detección de rostros...');
    
    // Preparar la imagen (rotar según EXIF)
    final preparedImage = await _prepareImage(_image!);
    
    final inputImage = InputImage.fromFile(preparedImage);
    
    // Iniciar el detector de rostros
    final faces = await _faceDetector.processImage(inputImage);

    setState(() {
      _faces = faces;
      _isProcessing = false;
    });
    print('✅ Detección completada. Rostros encontrados: ${faces.length}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detección de Rostros con ML Kit'),
        backgroundColor: Colors.indigoAccent,
      ),
      body: Column(
        children: [
          if (_faces != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Número de rostros detectados: ${_faces!.length}'),
            ),
          if (_image != null && _imageWidth != null && _imageHeight != null)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double scaleX = constraints.maxWidth / _imageWidth!;
                  final double scaleY = constraints.maxHeight / _imageHeight!;
                  final double scale = scaleX < scaleY ? scaleX : scaleY;
                  final double offsetX = (constraints.maxWidth - (_imageWidth! * scale)) / 2;
                  final double offsetY = (constraints.maxHeight - (_imageHeight! * scale)) / 2;

                  return Stack(
                    children: [
                      Center(
                        child: Image.file(
                          _image!,
                          fit: BoxFit.contain,
                          width: _imageWidth! * scale,
                          height: _imageHeight! * scale,
                        ),
                      ),
                      if (_faces != null)
                        for (var face in _faces!)
                          Positioned(
                            left: face.boundingBox.left * scale + offsetX,
                            top: face.boundingBox.top * scale + offsetY,
                            width: face.boundingBox.width * scale,
                            height: face.boundingBox.height * scale,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.red, width: 2),
                              ),
                            ),
                          ),
                    ],
                  );
                },
              ),
            ),
          if (_isProcessing)
            const CircularProgressIndicator(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: _pickImageFromCamera,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Usar Cámara'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo[300],
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _pickImageFromGallery,
                icon: const Icon(Icons.photo),
                label: const Text('Galería'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey[800],
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}