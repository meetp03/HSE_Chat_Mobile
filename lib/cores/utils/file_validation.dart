
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

enum FileCategory { IMAGE, VIDEO, AUDIO, DOCUMENT, GENERIC }

class FileValidationResult {
  final bool isValid;
  final String message;
  final File? file;
  final String? mime;
  final int? sizeBytes;
  final int? width;
  final int? height;
  final Duration? duration;
  final Map<String, dynamic>? extra;

  FileValidationResult({
    required this.isValid,
    required this.message,
    this.file,
    this.mime,
    this.sizeBytes,
    this.width,
    this.height,
    this.duration,
    this.extra,
  });
}

//Default rule sets (tweakable)
class ValidationRules {
  // Images
  static const imageExt = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.heic', '.heif', '.bmp'];
  static const imageMaxBytes = 10 * 1024 * 1024; // 10MB
  static const imageMaxWidth = 3840;
  static const imageMaxHeight = 2160;
  static const allowAnimatedGif = true;

  // Video
  static const videoExt = ['.mp4', '.mov', '.webm', '.3gp', '.mkv'];
  static const videoMaxBytes = 25 * 1024 * 1024; // 25MB
  static const videoMaxDurationSeconds = 60; // note: duration check optional

  // Audio
  static const audioExt = ['.mp3', '.m4a', '.wav', '.aac', '.3gp'];
  static const audioMaxBytes = 15 * 1024 * 1024; // 15MB
  static const audioMaxDurationSeconds = 120;

  // Documents
  static const docExt = ['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.csv'];
  static const docMaxBytes = 25 * 1024 * 1024; // 25MB
}

String _formatMb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

//Utility: sniff mime with headerBytes if possible (more reliable than extension)
Future<String?> _lookupMimeType(File file, {Uint8List? headerBytes}) async {
  try {
    if (headerBytes != null) {
      return lookupMimeType(file.path, headerBytes: headerBytes);
    }
    final bytesList = await file.openRead(0, 512).first;
    final bytes = Uint8List.fromList(bytesList);
    return lookupMimeType(file.path, headerBytes: bytes);
  } catch (_) {
    return lookupMimeType(file.path);
  }
}

// Image validation (dimensions + size + mime)
Future<FileValidationResult> validateImageFile(
  File file, {
  int? maxBytes,
  int? maxWidth,
  int? maxHeight,
  bool? allowAnimated,
}) async {
  maxBytes ??= ValidationRules.imageMaxBytes;
  maxWidth ??= ValidationRules.imageMaxWidth;
  maxHeight ??= ValidationRules.imageMaxHeight;
  allowAnimated ??= ValidationRules.allowAnimatedGif;

  final size = await file.length();
  if (size > maxBytes) {
    return FileValidationResult(
      isValid: false,
      message: 'Image is too large (${_formatMb(size)}). Maximum allowed is ${_formatMb(maxBytes)}. Try compressing or choose a smaller file.',
      file: file,
      sizeBytes: size,
    );
  }

  final mime = await _lookupMimeType(file);
  final extension = p.extension(file.path).toLowerCase();

  if (!ValidationRules.imageExt.contains(extension) && !(mime != null && mime.startsWith('image/'))) {
    return FileValidationResult(
      isValid: false,
      message: 'Unsupported image format "$extension". Allowed: ${ValidationRules.imageExt.join(', ')}.',
      file: file,
      mime: mime,
      sizeBytes: size,
    );
  }

  try {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final width = frame.image.width;
    final height = frame.image.height;
    final animated = codec.frameCount > 1;

    if (animated && !allowAnimated) {
      return FileValidationResult(
        isValid: false,
        message: 'Animated images are not allowed. Use a static JPG/PNG or enable animated support in settings.',
        file: file,
        mime: mime,
        sizeBytes: size,
        width: width,
        height: height,
      );
    }

    if (width > maxWidth || height > maxHeight) {
      return FileValidationResult(
        isValid: false,
        message: 'Image dimensions too large (${width}x$height). Maximum allowed is ${maxWidth}x$maxHeight. Consider resizing or cropping.',
        file: file,
        mime: mime,
        sizeBytes: size,
        width: width,
        height: height,
      );
    }

    return FileValidationResult(
      isValid: true,
      message: 'OK',
      file: file,
      mime: mime,
      sizeBytes: size,
      width: width,
      height: height,
      extra: {'animated': animated},
    );
  } catch (e) {
    return FileValidationResult(
      isValid: false,
      message: 'Unable to decode image. The file may be corrupted or an unsupported format.',
      file: file,
      sizeBytes: size,
    );
  }
}



// Video validation: size + mime (duration check is optional; see notes)
Future<FileValidationResult> validateVideoFile(
  File file, {
  int? maxBytes,
  int? maxDurationSec,
}) async {
  maxBytes ??= ValidationRules.videoMaxBytes;
  maxDurationSec ??= ValidationRules.videoMaxDurationSeconds;

  final size = await file.length();
  if (size > maxBytes) {
    return FileValidationResult(
      isValid: false,
      message: 'Video is too large (${_formatMb(size)}). Maximum allowed is ${_formatMb(maxBytes)}. Consider trimming or compressing the video.',
      file: file,
      sizeBytes: size,
    );
  }

  final mime = await _lookupMimeType(file);
  final extension = p.extension(file.path).toLowerCase();
  if (!ValidationRules.videoExt.contains(extension) && !(mime != null && mime.startsWith('video/'))) {
    return FileValidationResult(
      isValid: false,
      message: 'Unsupported video format "$extension". Allowed: ${ValidationRules.videoExt.join(', ')}.',
      file: file,
      mime: mime,
      sizeBytes: size,
    );
  }


  return FileValidationResult(
    isValid: true,
    message: 'OK',
    file: file,
    mime: mime,
    sizeBytes: size,
  );
}

// Audio validation: size + mime
Future<FileValidationResult> validateAudioFile(
  File file, {
  int? maxBytes,
}) async {
  maxBytes ??= ValidationRules.audioMaxBytes;

  final size = await file.length();
  if (size > maxBytes) {
    return FileValidationResult(
      isValid: false,
      message: 'Audio is too large (${_formatMb(size)}). Maximum allowed is ${_formatMb(maxBytes)}. Consider trimming or compressing the audio file.',
      file: file,
      sizeBytes: size,
    );
  }

  final mime = await _lookupMimeType(file);
  final extension = p.extension(file.path).toLowerCase();
  if (!ValidationRules.audioExt.contains(extension) && !(mime != null && mime.startsWith('audio/'))) {
    return FileValidationResult(
      isValid: false,
      message: 'Unsupported audio format "$extension". Allowed: ${ValidationRules.audioExt.join(', ')}.',
      file: file,
      mime: mime,
      sizeBytes: size,
    );
  }

  return FileValidationResult(
    isValid: true,
    message: 'OK',
    file: file,
    mime: mime,
    sizeBytes: size,
  );
}

//Document / generic file validation
Future<FileValidationResult> validateDocumentFile(
  File file, {
  int? maxBytes,
  List<String>? allowedExt,
}) async {
  maxBytes ??= ValidationRules.docMaxBytes;
  allowedExt ??= ValidationRules.docExt;

  final size = await file.length();
  if (size > maxBytes) {
    return FileValidationResult(
      isValid: false,
      message: 'File is too large (${_formatMb(size)}). Maximum allowed is ${_formatMb(maxBytes)}. Consider splitting or using a cloud link.',
      file: file,
      sizeBytes: size,
    );
  }

  final mime = await _lookupMimeType(file);
  final extension = p.extension(file.path).toLowerCase();
  if (!allowedExt.contains(extension) && !(mime != null && (mime.contains('pdf') || mime.contains('word') || mime.contains('officedocument')))) {
    return FileValidationResult(
      isValid: false,
      message: 'Unsupported document type "$extension". Allowed: ${allowedExt.join(', ')}.',
      file: file,
      mime: mime,
      sizeBytes: size,
    );
  }

  return FileValidationResult(
    isValid: true,
    message: 'OK',
    file: file,
    mime: mime,
    sizeBytes: size,
  );
}

//Generic router
Future<FileValidationResult> validateFileByCategory(File file, FileCategory cat) async {
  switch (cat) {
    case FileCategory.IMAGE:
      return validateImageFile(file);
    case FileCategory.VIDEO:
      return validateVideoFile(file);
    case FileCategory.AUDIO:
      return validateAudioFile(file);
    case FileCategory.DOCUMENT:
      return validateDocumentFile(file);
    default:
      final size = await file.length();
      final mime = await _lookupMimeType(file);
      return FileValidationResult(isValid: true, message: 'OK', file: file, mime: mime, sizeBytes: size);
  }
}
