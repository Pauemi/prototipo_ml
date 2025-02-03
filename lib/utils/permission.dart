import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

Future<bool> ensureStoragePermission() async {
  // Verifica la versión de Android.
  if (Platform.isAndroid && await _isAndroid11OrHigher()) {
    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      await openAppSettings(); // Abre configuración si el permiso está denegado permanentemente.
      return false;
    }
    status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  } else {
    // Para Android <= 10
    var status = await Permission.storage.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }
    status = await Permission.storage.request();
    return status.isGranted;
  }
}
 Future<bool> _isAndroid11OrHigher() async {
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
  
  // Verifica que estamos obteniendo un SDK válido (número entero)
  final sdkInt = androidInfo.version.sdkInt;

  // Para SDK >= 30 (Android 11)
  return sdkInt >= 30;
}
