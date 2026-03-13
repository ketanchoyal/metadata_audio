import 'package:audio_metadata/src/parse_error.dart';
import 'package:test/test.dart';

void main() {
  group('ParseError Hierarchy', () {
    test('CouldNotDetermineFileTypeError instantiates with message', () {
      const message = 'Unable to determine file type';
      final error = CouldNotDetermineFileTypeError(message);

      expect(error.message, equals(message));
      expect(error.name, equals('CouldNotDetermineFileTypeError'));
      expect(error.toString(), contains(message));
    });

    test('UnsupportedFileTypeError instantiates with message', () {
      const message = 'File type FLAC is not supported';
      final error = UnsupportedFileTypeError(message);

      expect(error.message, equals(message));
      expect(error.name, equals('UnsupportedFileTypeError'));
      expect(error.toString(), contains(message));
    });

    test('UnexpectedFileContentError includes fileType information', () {
      const fileType = 'mp3';
      const message = 'Invalid ID3 header';
      final error = UnexpectedFileContentError(fileType, message);

      expect(error.message, equals(message));
      expect(error.fileType, equals(fileType));
      expect(error.name, equals('UnexpectedFileContentError'));
      expect(error.toString(), contains(fileType));
      expect(error.toString(), contains(message));
    });

    test('FieldDecodingError instantiates with message', () {
      const message = 'Unable to decode UTF-8 field';
      final error = FieldDecodingError(message);

      expect(error.message, equals(message));
      expect(error.name, equals('FieldDecodingError'));
      expect(error.toString(), contains(message));
    });

    test('InternalParserError instantiates with message', () {
      const message = 'Unexpected state in parser';
      final error = InternalParserError(message);

      expect(error.message, equals(message));
      expect(error.name, equals('InternalParserError'));
      expect(error.toString(), contains(message));
    });

    test('All error types are instances of ParseError', () {
      expect(CouldNotDetermineFileTypeError('test'), isA<ParseError>());
      expect(UnsupportedFileTypeError('test'), isA<ParseError>());
      expect(UnexpectedFileContentError('mp3', 'test'), isA<ParseError>());
      expect(FieldDecodingError('test'), isA<ParseError>());
      expect(InternalParserError('test'), isA<ParseError>());
    });

    test('All error types implement Exception', () {
      expect(CouldNotDetermineFileTypeError('test'), isA<Exception>());
      expect(UnsupportedFileTypeError('test'), isA<Exception>());
      expect(UnexpectedFileContentError('mp3', 'test'), isA<Exception>());
      expect(FieldDecodingError('test'), isA<Exception>());
      expect(InternalParserError('test'), isA<Exception>());
    });
  });
}
