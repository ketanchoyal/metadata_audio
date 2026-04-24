import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:metadata_audio/src/native/api.dart' as api;
import 'package:metadata_audio/src/native/frb_generated.dart' show RustLib;
import 'package:metadata_audio/src/native/frb_generated.web.dart' as frb_web;

const String _webUnsupportedMessage =
    'metadata_audio WASM support is experimental; parse_from_path is not '
    'supported on web. Use parse_from_bytes with preloaded bytes instead.';

class MetadataAudioWeb {
  MetadataAudioWeb();

  static void registerWith(Registrar registrar) {
    _touchWebBindings();
  }

  static void _touchWebBindings() {
    // Keep the generated web bindings linked for the web plugin entry point.
    frb_web.wasmModule;
  }

  static Future<api.FfiAudioMetadata> parseFromPath({required String path}) {
    throw UnsupportedError(_webUnsupportedMessage);
  }

  static Future<api.FfiAudioMetadata> parseFromBytes({
    required Uint8List bytes,
    String? mimeHint,
  }) async {
    _touchWebBindings();
    await RustLib.init();
    return api.parseFromBytes(bytes: bytes, mimeHint: mimeHint);
  }
}
