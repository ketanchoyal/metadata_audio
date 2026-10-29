/// Unit tests for ASF `WM/Picture` decoding parity with upstream
/// music-metadata:
/// - Fields are read at their exact offsets (type byte, declared size, two
///   NUL-terminated UTF-16LE strings, then image data).
/// - Payloads shorter than 5 bytes are rejected as truncated headers.
/// - Unterminated UTF-16LE strings are rejected.
/// - A wrong or zero declared size must not truncate the decoded image data.
library;

import 'package:metadata_audio/src/asf/asf_object.dart';
import 'package:test/test.dart';

void main() {
  group('parseWmPicture', () {
    test('decodes fields at correct offsets and keeps complete data', () {
      final picture = parseWmPicture(<int>[
        0x03, // picture type: Cover (front)
        0x04, 0x00, 0x00, 0x00, // declared size (wrong on purpose)
        // MIME type 'image/gif' as UTF-16LE + NUL
        0x69, 0x00, 0x6D, 0x00, 0x61, 0x00, 0x67, 0x00, 0x65, 0x00, 0x2F,
        0x00, 0x67, 0x00, 0x69, 0x00, 0x66, 0x00, 0x00, 0x00,
        // description '' (just terminator)
        0x00, 0x00,
        // GIF-like payload, 6 bytes — longer than the declared size
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61,
      ]);

      expect(picture.type, equals('Cover (front)'));
      expect(picture.format, equals('image/gif'));
      expect(picture.description, isNull);
      expect(picture.data, hasLength(6));
      expect(picture.data, equals(<int>[0x47, 0x49, 0x46, 0x38, 0x39, 0x61]));
    });

    test('payload shorter than 5 bytes is rejected', () {
      expect(
        () => parseWmPicture(<int>[0x03, 0x00, 0x00, 0x00]),
        throwsA(
          isA<AsfContentParseError>().having(
            (e) => e.message,
            'message',
            contains('Truncated ASF picture header'),
          ),
        ),
      );
    });

    test('unterminated MIME type is rejected', () {
      expect(
        () => parseWmPicture(<int>[
          0x03,
          0x00, 0x00, 0x00, 0x00,
          0x69, 0x00, 0x6D, 0x00, // 'im' with no NUL terminator
        ]),
        throwsA(
          isA<AsfContentParseError>().having(
            (e) => e.message,
            'message',
            contains('Unterminated ASF picture MIME type'),
          ),
        ),
      );
    });

    test('unterminated description is rejected', () {
      expect(
        () => parseWmPicture(<int>[
          0x03,
          0x00, 0x00, 0x00, 0x00,
          // MIME 'jpeg' terminated
          0x6A, 0x00, 0x70, 0x00, 0x65, 0x00, 0x67, 0x00, 0x00, 0x00,
          // description 'Front' with no terminator
          0x46, 0x00, 0x72, 0x00, 0x6F, 0x00, 0x6E, 0x00, 0x74, 0x00,
        ]),
        throwsA(
          isA<AsfContentParseError>().having(
            (e) => e.message,
            'message',
            contains('Unterminated ASF picture description'),
          ),
        ),
      );
    });
  });
}
