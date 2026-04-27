library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:metadata_audio/src/core.dart' show parseBytes;
import 'package:metadata_audio/src/model/types.dart';
import 'package:web/web.dart' as web;

Future<AudioMetadata> parseWebFile(
  web.File file, {
  ParseOptions? options,
}) async {
  final mimeType = file.type.trim().isEmpty ? null : file.type;
  final arrayBuffer = await file.arrayBuffer().toDart;
  final bytes = arrayBuffer.toDart.asUint8List();

  return parseBytes(
    bytes,
    fileInfo: FileInfo(path: file.name, mimeType: mimeType, size: bytes.length),
    options: options,
  );
}
