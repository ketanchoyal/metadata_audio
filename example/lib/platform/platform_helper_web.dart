import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'platform_helper.dart';

WebPlatformHelper getPlatformHelper() => _WebPlatformHelper();

class _WebPlatformHelper implements WebPlatformHelper {
  @override
  Future<String?> downloadFile(
    List<int> bytes,
    String filename,
    String mimeType,
  ) async {
    final uint8List = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final blob = web.Blob(
      [uint8List.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = filename;
    anchor.style.display = 'none';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return filename;
  }

  @override
  String? createAudioUrl(List<int> bytes, String mimeType) {
    final uint8List = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final blob = web.Blob(
      [uint8List.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    return web.URL.createObjectURL(blob);
  }

  @override
  void revokeAudioUrl(String url) {
    web.URL.revokeObjectURL(url);
  }

  @override
  void openUrl(String url) {
    web.window.open(url, '_blank');
  }

  @override
  AudioPlayerService createAudioPlayer() => _WebAudioPlayer();
}

class _WebAudioPlayer implements AudioPlayerService {
  web.HTMLAudioElement? _audio;

  @override
  final ValueNotifier<bool> isPlaying = ValueNotifier(false);

  @override
  final ValueNotifier<double> currentPosition = ValueNotifier(0.0);

  @override
  final ValueNotifier<double> totalDuration = ValueNotifier(0.0);

  JSFunction? _onTimeUpdate;
  JSFunction? _onDurationChange;
  JSFunction? _onEnded;
  JSFunction? _onPlay;
  JSFunction? _onPause;

  _WebAudioPlayer() {
    final audio = web.document.createElement('audio') as web.HTMLAudioElement;
    _audio = audio;

    _onTimeUpdate = ((web.Event _) {
      currentPosition.value = audio.currentTime.toDouble();
    }).toJS;

    _onDurationChange = ((web.Event _) {
      if (audio.duration.isFinite) {
        totalDuration.value = audio.duration.toDouble();
      }
    }).toJS;

    _onEnded = ((web.Event _) {
      isPlaying.value = false;
      currentPosition.value = 0.0;
    }).toJS;

    _onPlay = ((web.Event _) {
      isPlaying.value = true;
    }).toJS;

    _onPause = ((web.Event _) {
      isPlaying.value = false;
    }).toJS;

    audio.addEventListener('timeupdate', _onTimeUpdate);
    audio.addEventListener('durationchange', _onDurationChange);
    audio.addEventListener('loadedmetadata', _onDurationChange);
    audio.addEventListener('ended', _onEnded);
    audio.addEventListener('play', _onPlay);
    audio.addEventListener('pause', _onPause);
  }

  @override
  void loadUrl(String url) {
    final audio = _audio;
    if (audio == null) return;
    audio.src = url;
    audio.load();
    currentPosition.value = 0.0;
    totalDuration.value = 0.0;
    isPlaying.value = false;
  }

  @override
  void play() {
    _audio?.play();
  }

  @override
  void pause() {
    _audio?.pause();
  }

  @override
  void seek(double seconds) {
    final audio = _audio;
    if (audio != null) {
      audio.currentTime = seconds;
      currentPosition.value = seconds;
    }
  }

  @override
  void stop() {
    final audio = _audio;
    if (audio != null) {
      audio.pause();
      audio.currentTime = 0.0;
      isPlaying.value = false;
      currentPosition.value = 0.0;
    }
  }

  @override
  void dispose() {
    final audio = _audio;
    if (audio != null) {
      audio.pause();
      if (_onTimeUpdate != null) {
        audio.removeEventListener('timeupdate', _onTimeUpdate);
      }
      if (_onDurationChange != null) {
        audio.removeEventListener('durationchange', _onDurationChange);
        audio.removeEventListener('loadedmetadata', _onDurationChange);
      }
      if (_onEnded != null) {
        audio.removeEventListener('ended', _onEnded);
      }
      if (_onPlay != null) {
        audio.removeEventListener('play', _onPlay);
      }
      if (_onPause != null) {
        audio.removeEventListener('pause', _onPause);
      }
      audio.remove();
      _audio = null;
    }
    isPlaying.dispose();
    currentPosition.dispose();
    totalDuration.dispose();
  }
}
