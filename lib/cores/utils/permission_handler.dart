import 'package:permission_handler/permission_handler.dart';
import '../constants/app_strings.dart';

class PermissionHandler {
  // Check camera permission
  static Future<bool> checkCameraPermission() async {
    return await Permission.camera.isGranted;
  }

  // Request camera permission
  static Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status == PermissionStatus.granted;
  }

  // Check storage permission
  static Future<bool> checkStoragePermission() async {
    return await Permission.storage.isGranted;
  }

  // Request storage permission
  static Future<bool> requestStoragePermission() async {
    final status = await Permission.storage.request();
    return status == PermissionStatus.granted;
  }

  // Check location permission
  static Future<bool> checkLocationPermission() async {
    return await Permission.location.isGranted;
  }

  // Request location permission
  static Future<bool> requestLocationPermission() async {
    final status = await Permission.location.request();
    return status == PermissionStatus.granted;
  }

  // Check microphone permission
  static Future<bool> checkMicrophonePermission() async {
    return await Permission.microphone.isGranted;
  }

  // Request microphone permission
  static Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status == PermissionStatus.granted;
  }

  // Check notification permission
  static Future<bool> checkNotificationPermission() async {
    return await Permission.notification.isGranted;
  }

  // Request notification permission
  static Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status == PermissionStatus.granted;
  }

  // Check and request camera permission with user-friendly handling
  static Future<bool> handleCameraPermission() async {
    if (await checkCameraPermission()) {
      return true;
    }

    final status = await Permission.camera.request();

    if (status == PermissionStatus.granted) {
      return true;
    } else if (status == PermissionStatus.permanentlyDenied) {
      await openAppSettings();
      return false;
    }

    return false;
  }

  // Check and request storage permission with user-friendly handling
  static Future<bool> handleStoragePermission() async {
    if (await checkStoragePermission()) {
      return true;
    }

    final status = await Permission.storage.request();

    if (status == PermissionStatus.granted) {
      return true;
    } else if (status == PermissionStatus.permanentlyDenied) {
      await openAppSettings();
      return false;
    }

    return false;
  }

  // Check and request location permission with user-friendly handling
  static Future<bool> handleLocationPermission() async {
    if (await checkLocationPermission()) {
      return true;
    }

    final status = await Permission.location.request();

    if (status == PermissionStatus.granted) {
      return true;
    } else if (status == PermissionStatus.permanentlyDenied) {
      await openAppSettings();
      return false;
    }

    return false;
  }

  // Get permission status message
  static String getPermissionMessage(Permission permission) {
    switch (permission) {
      case Permission.camera:
        return AppStr.cameraPermission;
      case Permission.storage:
        return AppStr.storagePermission;
      case Permission.location:
        return AppStr.locationPermission;
      default:
        return 'Permission required';
    }
  }
}
