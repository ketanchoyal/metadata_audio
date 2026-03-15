import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

void main() {
  group('metadata_audio package', () {
    test('package exports parse error types', () {
      expect(CouldNotDetermineFileTypeError('test'), isA<ParseError>());
      expect(UnsupportedFileTypeError('test'), isA<ParseError>());
      expect(UnexpectedFileContentError('mp3', 'test'), isA<ParseError>());
      expect(FieldDecodingError('test'), isA<ParseError>());
      expect(InternalParserError('test'), isA<ParseError>());
    });
  });
}
