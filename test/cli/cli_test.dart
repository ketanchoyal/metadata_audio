import 'dart:convert';
import 'dart:io';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/cli/cli_runner.dart';
import 'package:metadata_audio/src/cli/formatters/lrc_formatter.dart';
import 'package:test/test.dart';

import '../id3/id3_test_utils.dart';

void main() {
  group('CLI Runner', () {
    test('reports version on --version', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(['--version'], out: out, err: err);

      expect(code, 0);
      expect(out.toString(), contains('metadata_audio 1.0.0'));
      expect(err.toString(), isEmpty);
    });

    test('prints usage on --help', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(['--help'], out: out, err: err);

      expect(code, 0);
      expect(out.toString(), contains('Fast, stream-oriented audio metadata'));
      expect(out.toString(), contains('inspect'));
      expect(out.toString(), contains('chapters'));
      expect(out.toString(), contains('lyrics'));
    });

    test('prints usage when no args provided', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli([], out: out, err: err);

      expect(code, 0);
      expect(out.toString(), contains('Available commands:'));
    });

    test('returns 64 on unknown command', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(['unknown_command'], out: out, err: err);

      expect(code, 64);
      expect(err.toString(), contains('Could not find a command'));
    });
  });

  group('CLI Inspect Command', () {
    const mp3Sample = 'test/samples/mp3/id3v2.3.mp3';

    test('fails with 64 when file path is missing', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(['inspect'], out: out, err: err);

      expect(code, 64);
      expect(err.toString(), contains('Missing required audio file path or URL'));
    });

    test('fails with 65 when file does not exist', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(
        ['inspect', 'non_existent_file_12345.mp3'],
        out: out,
        err: err,
      );

      expect(code, 65);
      expect(err.toString(), contains('File error:'));
    });

    test('inspects sample audio file in table format', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(['inspect', mp3Sample, '--no-color'], out: out, err: err);

      expect(code, 0);
      final output = out.toString();
      expect(output, contains('Audio Format & Stream:'));
      expect(output, contains('Container'));
      expect(output, contains('Sample Rate'));
    });

    test('inspects sample audio file in JSON format', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(['inspect', mp3Sample, '--json'], out: out, err: err);

      expect(code, 0);
      final jsonOutput = out.toString();
      final parsed = jsonDecode(jsonOutput) as Map<String, dynamic>;
      expect(parsed.containsKey('format'), isTrue);
      expect(parsed.containsKey('common'), isTrue);
      expect(parsed.containsKey('quality'), isTrue);
    });

    test('inspects with --full to include native tags', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(
        ['inspect', mp3Sample, '--full', '--no-color'],
        out: out,
        err: err,
      );

      expect(code, 0);
      final output = out.toString();
      expect(output, contains('Native Tags:'));
    });
  });

  group('CLI Chapters Command', () {
    const chaptersSampleM4a = 'test/samples/mp4/sample.m4a';
    const noChaptersMp3 = 'test/samples/mp3/id3v2.3.mp3';

    test('fails with 64 on missing argument for list', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(['chapters', 'list'], out: out, err: err);

      expect(code, 64);
      expect(err.toString(), contains('Missing required audio file path or URL'));
    });

    test('notifies when file has no chapters', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(['chapters', 'list', noChaptersMp3], out: out, err: err);

      expect(code, 0);
      expect(out.toString(), contains('No embedded chapters found'));
    });

    test('lists chapters formatted as table', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(
        ['chapters', 'list', chaptersSampleM4a, '--no-color'],
        out: out,
        err: err,
      );

      expect(code, 0);
      final output = out.toString();
      expect(output, contains('Start'));
      expect(output, contains('End'));
      expect(output, contains('Title'));
      expect(output, contains('Chapter 1'));
    });

    test('fails with 64 on invalid chapter index', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(
        ['chapters', 'extract', chaptersSampleM4a, '--index=999'],
        out: out,
        err: err,
      );

      expect(code, 64);
      expect(err.toString(), contains('Invalid chapter index'));
    });

    test('extracts a chapter successfully to a temp directory', () async {
      final tempDir = await Directory.systemTemp.createTemp('cli_chap_test_');
      try {
        final out = StringBuffer();
        final err = StringBuffer();
        final code = await runCli(
          [
            'chapters',
            'extract',
            chaptersSampleM4a,
            '-o',
            tempDir.path,
            '--index=1',
          ],
          out: out,
          err: err,
        );

        expect(code, 0);
        expect(out.toString(), contains('Extracting 1 chapter(s)'));
        expect(out.toString(), contains('[✓] Chapter 1:'));

        final generatedFiles = tempDir.listSync();
        expect(generatedFiles.isNotEmpty, isTrue);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });

  group('CLI Lyrics Command & LrcFormatter', () {
    late Directory tempDir;
    late File lyricsMp3;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('cli_lyrics_test_');

      // Create an MP3 file with USLT frame
      final uslt = buildId3v24Frame('USLT', [
        0x03, // UTF-8
        ...ascii.encode('eng'),
        ...utf8.encode(''),
        0x00,
        ...utf8.encode('[00:05.50]First line\n[00:15.20]Second line'),
        0x00,
      ]);
      final tit2 = buildId3v24Frame('TIT2', [
        0x03,
        ...utf8.encode('Test Song'),
        0x00,
      ]);
      final tpe1 = buildId3v24Frame('TPE1', [
        0x03,
        ...utf8.encode('Test Artist'),
        0x00,
      ]);

      final tagBytes = buildId3Tag(
        majorVersion: 4,
        revision: 0,
        flags: 0,
        payload: [...tit2, ...tpe1, ...uslt],
      );
      lyricsMp3 = File('${tempDir.path}/song_with_lyrics.mp3');
      await lyricsMp3.writeAsBytes([...tagBytes, 0xFF, 0xFB, 0x90, 0x00]);
    });

    tearDownAll(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('exports lyrics in LRC format to stdout', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(['lyrics', lyricsMp3.path], out: out, err: err);

      expect(code, 0);
      final text = out.toString();
      expect(text, contains('[ti:Test Song]'));
      expect(text, contains('[ar:Test Artist]'));
      expect(text, contains('[00:05.50]First line'));
      expect(text, contains('[00:15.20]Second line'));
    });

    test('exports lyrics in plain text format', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(
        ['lyrics', lyricsMp3.path, '--format=txt'],
        out: out,
        err: err,
      );

      expect(code, 0);
      final text = out.toString();
      expect(text, contains('First line'));
      expect(text, contains('Second line'));
    });

    test('exports lyrics to file with --output', () async {
      final targetFile = '${tempDir.path}/extracted.lrc';
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(
        ['lyrics', lyricsMp3.path, '--output', targetFile],
        out: out,
        err: err,
      );

      expect(code, 0);
      expect(out.toString(), contains('Lyrics written to $targetFile'));
      final written = await File(targetFile).readAsString();
      expect(written, contains('[ti:Test Song]'));
      expect(written, contains('[00:05.50]First line'));
    });

    test('returns 1 when file has no lyrics', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(
        ['lyrics', 'test/samples/mp3/id3v2.3.mp3'],
        out: out,
        err: err,
      );

      expect(code, 1);
      expect(err.toString(), contains('No embedded lyrics found'));
    });

    test('LrcFormatter formats syncText correctly with timestamps', () {
      const tag = LyricsTag(
        contentType: 'lyrics',
        timeStampFormat: 'ms',
        syncText: [
          LyricsText(text: 'Hello world', timestamp: 65430),
          LyricsText(text: 'Another line', timestamp: 125000),
        ],
      );

      final formatted = LrcFormatter.format(
        tag,
        title: 'Track Title',
        artist: 'Singer',
        album: 'Record',
      );

      expect(formatted, contains('[ti:Track Title]'));
      expect(formatted, contains('[ar:Singer]'));
      expect(formatted, contains('[al:Record]'));
      expect(formatted, contains('[01:05.43]Hello world'));
      expect(formatted, contains('[02:05.00]Another line'));
    });
  });
}
