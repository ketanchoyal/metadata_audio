import 'package:flutter/foundation.dart';
import 'platform_helper.dart';

WebPlatformHelper getPlatformHelper() => _StubPlatformHelper();

class _StubPlatformHelper implements WebPlatformHelper {
  @override
  void downloadFile(List<int> bytes, String filename, String mimeType) {}

  @override
  String? createAudioUrl(List<int> bytes, String mimeType) => null;

  @override
  void revokeAudioUrl(String url) {}

  @override
  void openUrl(String url) {}

  @override
  AudioPlayerService createAudioPlayer() => _StubAudioPlayer();
}

class _StubAudioPlayer implements AudioPlayerService {
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
