import 'dart:io';
import 'package:path_provider/path_provider.dart';

class GalleryHelper {
  // Save an image file at [filePath] to a Pictures folder. Returns true on success.
  static Future<bool?> saveImage(String filePath) async {
    try {
      final src = File(filePath);
      if (!await src.exists()) return false;

      final destDir = await _getDestinationDir();
      if (destDir == null) return false;
      final dest = File('${destDir.path}${Platform.pathSeparator}\$fileName');
      await destDir.create(recursive: true);
      await src.copy(dest.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  // Save a video file at [filePath] to a Videos folder. Returns true on success.
  static Future<bool?> saveVideo(String filePath) async {
    // For simplicity, use same destination as images
    return saveImage(filePath);
  }

  static Future<Directory?> _getDestinationDir() async {
    try {
      if (Platform.isAndroid) {
        final dir = (await getExternalStorageDirectory());
        if (dir == null) return null;
        final path = Directory(
          '${dir.path}${Platform.pathSeparator}Pictures${Platform.pathSeparator}HSC_Chat',
        );
        return path;
      } else if (Platform.isIOS) {
        final dir = await getApplicationDocumentsDirectory();
        final path = Directory('${dir.path}${Platform.pathSeparator}HSC_Chat');
        return path;
      } else {
        final dir = await getTemporaryDirectory();
        return Directory('${dir.path}${Platform.pathSeparator}HSC_Chat');
      }
    } catch (_) {
      return null;
    }
  }
}
