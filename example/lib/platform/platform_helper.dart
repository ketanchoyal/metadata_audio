import 'package:flutter/foundation.dart';
import 'platform_helper_stub.dart'
    if (dart.library.js_interop) 'platform_helper_web.dart'
    if (dart.library.io) 'platform_helper_io.dart';

abstract class WebPlatformHelper {
  static WebPlatformHelper get instance => getPlatformHelper();

  Future<String?> downloadFile(
    List<int> bytes,
    String filename,
    String mimeType,
  );
  String? createAudioUrl(List<int> bytes, String mimeType);
  void revokeAudioUrl(String url);
  void openUrl(String url);

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

/// Shared no-op [AudioPlayerService] used when browser audio playback is not
/// active (e.g. non-web platforms or stub targets).
class NoopAudioPlayer implements AudioPlayerService {
  @override
  final ValueNotifier<bool> isPlaying = ValueNotifier(false);

  @override
  final ValueNotifier<double> currentPosition = ValueNotifier(0.0);

  @override
  final ValueNotifier<double> totalDuration = ValueNotifier(0.0);

  @override
  void loadUrl(String url) {}

  @override
  void play() {
    isPlaying.value = true;
  }

  @override
  void pause() {
    isPlaying.value = false;
  }

  @override
  void seek(double seconds) {
    currentPosition.value = seconds;
  }

  @override
  void stop() {
    isPlaying.value = false;
    currentPosition.value = 0.0;
  }

  @override
  void dispose() {
    isPlaying.dispose();
    currentPosition.dispose();
    totalDuration.dispose();
  }
}
