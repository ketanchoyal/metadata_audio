import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'platform_helper.dart';

WebPlatformHelper getPlatformHelper() => _IoPlatformHelper();

class _IoPlatformHelper implements WebPlatformHelper {
  @override
  Future<String?> downloadFile(
    List<int> bytes,
    String filename,
    String mimeType,
  ) async {
    final dotIndex = filename.lastIndexOf('.');
    final ext = (dotIndex != -1 && dotIndex + 1 < filename.length)
        ? filename.substring(dotIndex + 1).toLowerCase()
        : null;

    var savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save file to:',
      fileName: filename,
      type: ext != null ? FileType.custom : FileType.any,
      allowedExtensions: ext != null ? [ext] : null,
    );

    if (savePath == null || savePath.isEmpty) {
      return null;
    }

    if (ext != null && !savePath.toLowerCase().endsWith('.$ext')) {
      savePath = '$savePath.$ext';
    }

    await File(savePath).writeAsBytes(bytes);
    return savePath;
  }

  @override
  String? createAudioUrl(List<int> bytes, String mimeType) => null;

  @override
  void revokeAudioUrl(String url) {}

  @override
  void openUrl(String url) {}

  @override
  AudioPlayerService createAudioPlayer() => NoopAudioPlayer();
}
