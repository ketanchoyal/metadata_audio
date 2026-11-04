import 'package:flutter/foundation.dart';
import 'platform_helper_stub.dart'
    if (dart.library.js_interop) 'platform_helper_web.dart';

abstract class WebPlatformHelper {
  static WebPlatformHelper get instance => getPlatformHelper();

  void downloadFile(List<int> bytes, String filename, String mimeType);
  String? createAudioUrl(List<int> bytes, String mimeType);
  void revokeAudioUrl(String url);

  AudioPlayerService createAudioPlayer();
}

abstract class AudioPlayerService {
  ValueNotifier<bool> get isPlaying;
  ValueNotifier<double> get currentPosition;
  ValueNotifier<double> get totalDuration;

  void loadUrl(String url);
  void play();
  void pause();
  void seek(double seconds);
  void stop();
  void dispose();
}
