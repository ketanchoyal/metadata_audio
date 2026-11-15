import 'dart:convert';
import 'dart:io';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/cli/cli_runner.dart';
import 'package:metadata_audio/src/cli/formatters/lrc_formatter.dart';
import 'package:metadata_audio/src/cli/formatters/table_formatter.dart';
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

    test('subcommands support --help flag', () async {
      for (final cmd in ['inspect', 'chapters', 'lyrics']) {
        final out = StringBuffer();
        final err = StringBuffer();
        final code = await runCli([cmd, '--help'], out: out, err: err);

        expect(code, 0);
        expect(out.toString(), contains('Usage: metadata_audio $cmd'));
        expect(err.toString(), isEmpty);
      }
    });

    test('chapters extract supports --help flag', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(['chapters', 'extract', '--help'], out: out, err: err);

      expect(code, 0);
      expect(out.toString(), contains('--output-dir'));
      expect(out.toString(), contains('--index'));
    });
  });

  group('CLI Inspect Command', () {
    const mp3Sample = 'test/samples/mp3/id3v2.3.mp3';
    const flacSample = 'test/samples/flac/sample.flac';
    const oggSample = 'test/samples/ogg/vorbis.ogg';

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

    test('inspects with --no-duration and --no-covers flags', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(
        ['inspect', mp3Sample, '--no-duration', '--no-covers', '--json'],
        out: out,
        err: err,
      );

      expect(code, 0);
      final parsed = jsonDecode(out.toString()) as Map<String, dynamic>;
      expect(parsed['format'], isNotNull);
    });

    test('inspects FLAC and Ogg Vorbis formats successfully', () async {
      for (final sample in [flacSample, oggSample]) {
        final file = File(sample);
        if (!file.existsSync()) continue;

        final out = StringBuffer();
        final err = StringBuffer();
        final code = await runCli(['inspect', sample, '--no-color'], out: out, err: err);

        expect(code, 0);
        expect(out.toString(), contains('Audio Format & Stream:'));
      }
    });

    test('inspects audio file over local HTTP URL', () async {
      final file = File(mp3Sample);
      final bytes = await file.readAsBytes();

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response.headers
          ..set('Content-Type', 'audio/mpeg')
          ..set('Accept-Ranges', 'bytes');
        request.response.add(bytes);
        request.response.close();
      });

      try {
        final url = 'http://127.0.0.1:${server.port}/sample.mp3';
        final out = StringBuffer();
        final err = StringBuffer();
        final code = await runCli(['inspect', url, '--no-color'], out: out, err: err);

        expect(code, 0);
        expect(out.toString(), contains('Audio Format & Stream:'));
        expect(out.toString(), contains('MPEG'));
      } finally {
        await server.close(force: true);
      }
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

    test('lists chapters with --color flag', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(
        ['chapters', 'list', chaptersSampleM4a, '--color'],
        out: out,
        err: err,
      );

      expect(code, 0);
      expect(out.toString(), contains('Chapter 1'));
    });

    test('fails with 64 on invalid chapter index (out of range)', () async {
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

    test('fails with 64 on zero or negative chapter index', () async {
      for (final badIndex in ['0', '-1', 'abc']) {
        final out = StringBuffer();
        final err = StringBuffer();
        final code = await runCli(
          ['chapters', 'extract', chaptersSampleM4a, '--index=$badIndex'],
          out: out,
          err: err,
        );

        expect(code, 64);
        expect(err.toString(), contains('Invalid chapter index'));
      }
    });

    test('extracts chapter into newly created nested directory', () async {
      final tempBase = await Directory.systemTemp.createTemp('cli_chap_test_');
      final nestedDir = Directory('${tempBase.path}/deep/nested/output');
      try {
        final out = StringBuffer();
        final err = StringBuffer();
        final code = await runCli(
          [
            'chapters',
            'extract',
            chaptersSampleM4a,
            '-o',
            nestedDir.path,
            '--index=1',
          ],
          out: out,
          err: err,
        );

        expect(code, 0);
        expect(out.toString(), contains('Extracting 1 chapter(s)'));
        expect(out.toString(), contains('[✓] Chapter 1:'));
        expect(await nestedDir.exists(), isTrue);

        final files = nestedDir.listSync();
        expect(files.isNotEmpty, isTrue);
      } finally {
        if (await tempBase.exists()) {
          await tempBase.delete(recursive: true);
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

    test('exports lyrics in plain text format to stdout', () async {
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

    test('exports lyrics in plain text format to file', () async {
      final targetFile = '${tempDir.path}/lyrics_plain.txt';
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(
        ['lyrics', lyricsMp3.path, '--format=txt', '--output', targetFile],
        out: out,
        err: err,
      );

      expect(code, 0);
      expect(out.toString(), contains('Lyrics written to $targetFile'));
      final written = await File(targetFile).readAsString();
      expect(written, contains('First line'));
      expect(written, contains('Second line'));
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

    test('LrcFormatter handles empty metadata headers and lines without timestamp', () {
      const tag = LyricsTag(
        contentType: 'lyrics',
        timeStampFormat: 'ms',
        syncText: [
          LyricsText(text: 'No timestamp line'),
        ],
      );

      final formatted = LrcFormatter.format(
        tag,
        title: '   ',
        album: '',
      );

      expect(formatted.contains('[ti:'), isFalse);
      expect(formatted.contains('[ar:'), isFalse);
      expect(formatted.contains('[al:'), isFalse);
      expect(formatted, contains('No timestamp line'));
    });

    test('LrcFormatter falls back to text when syncText is empty', () {
      const tag = LyricsTag(
        contentType: 'lyrics',
        timeStampFormat: 'ms',
        syncText: [],
        text: 'Unsynchronized lyric paragraph',
      );

      final formatted = LrcFormatter.format(tag);
      expect(formatted, contains('Unsynchronized lyric paragraph'));
    });
  });

  group('TableFormatter Unit Tests', () {
    const emptyCommon = CommonTags(
      track: TrackNo(),
      disk: TrackNo(),
      movementIndex: TrackNo(),
    );
    const emptyQuality = QualityInformation();

    test('formats channel labels correctly', () {
      final formatter = TableFormatter(enableColor: false);
      const metaMono = AudioMetadata(
        format: Format(numberOfChannels: 1),
        native: {},
        common: emptyCommon,
        quality: emptyQuality,
      );
      const metaStereo = AudioMetadata(
        format: Format(numberOfChannels: 2),
        native: {},
        common: emptyCommon,
        quality: emptyQuality,
      );
      const meta51 = AudioMetadata(
        format: Format(numberOfChannels: 6),
        native: {},
        common: emptyCommon,
        quality: emptyQuality,
      );
      const meta71 = AudioMetadata(
        format: Format(numberOfChannels: 8),
        native: {},
        common: emptyCommon,
        quality: emptyQuality,
      );

      expect(formatter.formatMetadata(metaMono), contains('(Mono)'));
      expect(formatter.formatMetadata(metaStereo), contains('(Stereo)'));
      expect(formatter.formatMetadata(meta51), contains('(5.1 Surround)'));
      expect(formatter.formatMetadata(meta71), contains('(7.1 Surround)'));
    });

    test('formats duration for short and long audio files', () {
      final formatter = TableFormatter(enableColor: false);
      const shortMeta = AudioMetadata(
        format: Format(duration: 45.5),
        native: {},
        common: emptyCommon,
        quality: emptyQuality,
      );
      const longMeta = AudioMetadata(
        format: Format(duration: 3665.25), // 1h 1m 5s
        native: {},
        common: emptyCommon,
        quality: emptyQuality,
      );

      expect(formatter.formatMetadata(shortMeta), contains('0m 45s'));
      expect(formatter.formatMetadata(longMeta), contains('1h 1m 5s'));
    });

    test('formats ReplayGain and warnings', () {
      final formatter = TableFormatter(enableColor: false);
      const meta = AudioMetadata(
        format: Format(),
        native: {},
        common: CommonTags(
          track: TrackNo(),
          disk: TrackNo(),
          movementIndex: TrackNo(),
          replaygain_track_gain: Ratio(ratio: 0.8, dB: -1.94),
          replaygain_track_peak: Ratio(ratio: 0.98),
          replaygain_album_gain: Ratio(ratio: 0.75, dB: -2.50),
          replaygain_album_peak: Ratio(ratio: 0.95),
        ),
        quality: QualityInformation(
          warnings: [ParserWarning(message: 'Sample test warning')],
        ),
      );

      final text = formatter.formatMetadata(meta);
      expect(text, contains('ReplayGain:'));
      expect(text, contains('Track Gain'));
      expect(text, contains('-1.94 dB'));
      expect(text, contains('Album Gain'));
      expect(text, contains('-2.50 dB'));
      expect(text, contains('Warnings:'));
      expect(text, contains('Sample test warning'));
    });

    test('formatChapters formats chapters with default titles and durations', () {
      final formatter = TableFormatter(enableColor: false);
      final chapters = [
        const Chapter(title: '', start: 0, end: 125000),
        const Chapter(title: 'Chapter Two', start: 125000, end: 300000),
      ];

      final output = formatter.formatChapters(chapters, source: 'test.m4b');
      expect(output, contains('=== Chapters: test.m4b ==='));
      expect(output, contains('Chapter 1'));
      expect(output, contains('Chapter Two'));
      expect(output, contains('02:05.0'));
    });
  });
}
