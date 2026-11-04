import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

void main() {
  group('metadata_audio package', () {
    test('package exports parse error types', () {
      expect(const CouldNotDetermineFileTypeError('test'), isA<ParseError>());
      expect(const UnsupportedFileTypeError('test'), isA<ParseError>());
      expect(
        const UnexpectedFileContentError('mp3', 'test'),
        isA<ParseError>(),
      );
      expect(const FieldDecodingError('test'), isA<ParseError>());
      expect(const InternalParserError('test'), isA<ParseError>());
    });
  });
}
