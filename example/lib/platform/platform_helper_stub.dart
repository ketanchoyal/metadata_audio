import 'platform_helper.dart';

WebPlatformHelper getPlatformHelper() => _StubPlatformHelper();

class _StubPlatformHelper implements WebPlatformHelper {
  @override
  Future<String?> downloadFile(
    List<int> bytes,
    String filename,
    String mimeType,
  ) async => null;

  @override
  String? createAudioUrl(List<int> bytes, String mimeType) => null;

  @override
  void revokeAudioUrl(String url) {}

  @override
  void openUrl(String url) {}

  @override
  AudioPlayerService createAudioPlayer() => NoopAudioPlayer();
}
