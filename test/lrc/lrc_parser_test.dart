import 'package:audio_metadata/src/lrc/lrc_parser.dart';
import 'package:test/test.dart';

void main() {
  group('LrcParser', () {
    test('parses synchronized lyrics with timestamps', () {
      const lrcContent = '''[ti:Test Song]
[ar:Test Artist]
[al:Test Album]
[00:00.00]First line
[00:05.00]Second line
[00:10.50]Third line''';

      final result = LrcParser.parseLyrics(lrcContent);

      expect(result.contentType, equals('lyrics'));
      expect(result.timeStampFormat, equals('milliseconds'));
      expect(result.syncText, hasLength(3));
      expect(result.syncText[0].text, equals('First line'));
      expect(result.syncText[0].timestamp, equals(0));
      expect(result.syncText[1].text, equals('Second line'));
      expect(result.syncText[1].timestamp, equals(5000));
      expect(result.syncText[2].text, equals('Third line'));
      expect(result.syncText[2].timestamp, equals(10500));
    });

    test('parses milliseconds with 3-digit precision', () {
      const lrcContent = '[00:01.250]Lyrics with milliseconds';

      final result = LrcParser.parseLyrics(lrcContent);

      expect(result.syncText, hasLength(1));
      expect(result.syncText[0].timestamp, equals(1250));
      expect(result.syncText[0].text, equals('Lyrics with milliseconds'));
    });

    test('parses centiseconds with 2-digit precision', () {
      const lrcContent = '[00:01.25]Lyrics with centiseconds';

      final result = LrcParser.parseLyrics(lrcContent);

      expect(result.syncText, hasLength(1));
      expect(result.syncText[0].timestamp, equals(1250));
      expect(result.syncText[0].text, equals('Lyrics with centiseconds'));
    });

    test('handles minutes and seconds correctly', () {
      const lrcContent = '[02:30.50]Line at 2 minutes 30 seconds';

      final result = LrcParser.parseLyrics(lrcContent);

      expect(result.syncText, hasLength(1));
      expect(result.syncText[0].timestamp, equals((2 * 60 + 30) * 1000 + 500));
    });

    test('parses metadata tags', () {
      const lrcContent = '''[ti:My Title]
[ar:My Artist]
[al:My Album]
[re:Editor Name]
[la:en]
[00:00.00]First line''';

      final result = LrcParser.parseLyrics(lrcContent);

      expect(result.descriptor, equals('Editor Name'));
      expect(result.language, equals('en'));
    });

    test('combines multiple lyrics into text field', () {
      const lrcContent = '''[00:00.00]Line 1
[00:05.00]Line 2
[00:10.00]Line 3''';

      final result = LrcParser.parseLyrics(lrcContent);

      expect(result.text, equals('Line 1\nLine 2\nLine 3'));
    });

    test('handles unsynchronized lyrics', () {
      const unsyncedLyrics =
          'This is plain text\nwithout timestamps\nno sync info';

      final result = LrcParser.parseLyrics(unsyncedLyrics);

      expect(result.contentType, equals('lyrics'));
      expect(result.timeStampFormat, equals('unsynchronized'));
      expect(result.text, equals(unsyncedLyrics));
      expect(result.syncText, isEmpty);
    });

    test('handles empty lines', () {
      const lrcContent = '''[00:00.00]First line

[00:05.00]Second line

[00:10.00]Third line''';

      final result = LrcParser.parseLyrics(lrcContent);

      expect(result.syncText, hasLength(3));
      expect(result.syncText[0].text, equals('First line'));
      expect(result.syncText[1].text, equals('Second line'));
      expect(result.syncText[2].text, equals('Third line'));
    });

    test('handles multiple timestamps on same line', () {
      const lrcContent =
          '''[00:00.00][00:10.00]Lyrics with multiple timestamps''';

      final result = LrcParser.parseLyrics(lrcContent);

      // Should have entries for each timestamp
      expect(result.syncText, isNotEmpty);
    });

    test('handles metadata-only content as unsynchronized', () {
      const lrcContent = '[ti:Title Only]';

      final result = LrcParser.parseLyrics(lrcContent);

      expect(result.timeStampFormat, equals('unsynchronized'));
      expect(result.text, equals('[ti:Title Only]'));
    });

    test('handles special characters in lyrics', () {
      const lrcContent = '[00:00.00]Line with special chars: @#\$%^&*()';

      final result = LrcParser.parseLyrics(lrcContent);

      expect(result.syncText[0].text, contains('@'));
      expect(result.syncText[0].text, contains('\$'));
    });

    test('trims whitespace from lyrics', () {
      const lrcContent = '[00:00.00]   Lyrics with leading spaces   ';

      final result = LrcParser.parseLyrics(lrcContent);

      expect(result.syncText[0].text, equals('Lyrics with leading spaces'));
    });
  });
}
