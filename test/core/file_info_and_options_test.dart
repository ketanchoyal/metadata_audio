import 'package:audio_metadata/src/model/types.dart';
import 'package:test/test.dart';

void main() {
  group('FileInfo', () {
    test('creates FileInfo with all parameters', () {
      const info = FileInfo(
        path: '/path/to/file.mp3',
        mimeType: 'audio/mpeg',
        size: 5242880,
        url: 'http://example.com/file.mp3',
      );

      expect(info.path, equals('/path/to/file.mp3'));
      expect(info.mimeType, equals('audio/mpeg'));
      expect(info.size, equals(5242880));
      expect(info.url, equals('http://example.com/file.mp3'));
    });

    test('creates FileInfo with optional parameters', () {
      const info = FileInfo(path: '/path/to/file.mp3');

      expect(info.path, equals('/path/to/file.mp3'));
      expect(info.mimeType, isNull);
      expect(info.size, isNull);
      expect(info.url, isNull);
    });

    test('creates empty FileInfo', () {
      const info = FileInfo();

      expect(info.path, isNull);
      expect(info.mimeType, isNull);
      expect(info.size, isNull);
      expect(info.url, isNull);
    });

    test('FileInfo.fromPath factory', () {
      final info = FileInfo.fromPath('/path/to/file.mp3');

      expect(info.path, equals('/path/to/file.mp3'));
      expect(info.mimeType, isNull);
    });

    test('FileInfo.fromUrl factory', () {
      final info = FileInfo.fromUrl('http://example.com/file.mp3');

      expect(info.url, equals('http://example.com/file.mp3'));
      expect(info.path, isNull);
    });

    test('FileInfo.withMimeType factory', () {
      final info = FileInfo.withMimeType('/path/to/file.mp3', 'audio/mpeg');

      expect(info.path, equals('/path/to/file.mp3'));
      expect(info.mimeType, equals('audio/mpeg'));
      expect(info.size, isNull);
    });

    test('FileInfo is const when possible', () {
      const info1 = FileInfo(path: '/same/path.mp3');
      const info2 = FileInfo(path: '/same/path.mp3');

      expect(identical(info1, info2), isTrue);
    });
  });

  group('ParseOptions', () {
    test('creates ParseOptions with default values', () {
      const options = ParseOptions();

      expect(options.skipCovers, isFalse);
      expect(options.skipPostHeaders, isFalse);
      expect(options.includeChapters, isFalse);
      expect(options.duration, isFalse);
      expect(options.observer, isNull);
    });

    test('creates ParseOptions with custom values', () {
      void observer(MetadataEvent event) {}

      final options = ParseOptions(
        skipCovers: true,
        skipPostHeaders: true,
        includeChapters: true,
        duration: true,
        observer: observer,
      );

      expect(options.skipCovers, isTrue);
      expect(options.skipPostHeaders, isTrue);
      expect(options.includeChapters, isTrue);
      expect(options.duration, isTrue);
      expect(options.observer, equals(observer));
    });

    test('ParseOptions.all() factory enables all features', () {
      final options = ParseOptions.all();

      expect(options.skipCovers, isFalse);
      expect(options.skipPostHeaders, isFalse);
      expect(options.includeChapters, isTrue);
      expect(options.duration, isTrue);
    });

    test('ParseOptions.minimal() factory disables features', () {
      final options = ParseOptions.minimal();

      expect(options.skipCovers, isTrue);
      expect(options.skipPostHeaders, isTrue);
      expect(options.includeChapters, isFalse);
      expect(options.duration, isFalse);
    });

    test('ParseOptions.metadataOnly() factory', () {
      final options = ParseOptions.metadataOnly();

      expect(options.skipCovers, isFalse);
      expect(options.skipPostHeaders, isTrue);
      expect(options.includeChapters, isFalse);
      expect(options.duration, isFalse);
    });

    test('ParseOptions is const when possible', () {
      const opts1 = ParseOptions(duration: true);
      const opts2 = ParseOptions(duration: true);

      expect(identical(opts1, opts2), isTrue);
    });

    test('ParseOptions observer can be set', () {
      var called = false;
      void observer(MetadataEvent event) => called = true;

      final options = ParseOptions(observer: observer);
      options.observer!(const MetadataEvent());

      expect(called, isTrue);
    });
  });
}
