// Smoke test for the example app shell.
//
// Verifies the main layout renders: the sidebar header, the Local/Remote
// tabs, the parser configuration switches, plus the Streams & Tracks card
// and the common-tag chips builders.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/desktop_screen.dart';
import 'package:example/main.dart';
import 'package:example/web_analyzer_screen.dart';
import 'package:metadata_audio/metadata_audio.dart';

/// Synthetic metadata with two streams (Vorbis audio + Theora video),
/// mimicking what an Ogg muxed file reports via `format.trackInfo`.
AudioMetadata _metadataWithTracks() {
  const audioTrack = TrackInfo(
    type: TrackType.audio,
    codecName: 'Vorbis',
    id: 1,
    duration: 12.34,
    bitrate: 128000,
    lossless: false,
    audio: AudioTrack(
      samplingFrequency: 44100,
      channels: 2,
      bitDepth: 16,
      numberOfSamples: 544000,
    ),
  );
  const videoTrack = TrackInfo(
    type: TrackType.video,
    codecId: 'theo',
    id: 2,
    duration: 12.5,
    video: VideoTrack(pixelWidth: 640, pixelHeight: 480, frameRate: 30),
  );
  const common = CommonTags(
    track: TrackNo(no: 3, of: 10),
    disk: TrackNo(),
    movementIndex: TrackNo(no: 2, of: 4),
    movement: 'Allegro',
    tvShow: 'Storytime',
    podcastId: 'podcast-123',
    playCounter: 42,
    peakLevel: 28000,
    averageLevel: 31000,
  );
  return const AudioMetadata(
    format: Format(container: 'ogg', trackInfo: [audioTrack, videoTrack]),
    native: {},
    common: common,
    quality: QualityInformation(),
  );
}

void main() {
  testWidgets('app shell renders tabs and parser configuration', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Sidebar header.
    expect(find.text('Metadata Audio'), findsOneWidget);

    // Navigation tabs for local vs remote parsing.
    expect(find.text('Local File'), findsOneWidget);
    expect(find.text('Remote URL'), findsOneWidget);

    // Parser configuration switches.
    expect(find.text('Extract Chapters'), findsOneWidget);
    expect(find.text('Calculate Duration'), findsOneWidget);
    expect(find.text('Skip Cover Images'), findsOneWidget);
    expect(find.text('Skip Post Headers'), findsOneWidget);
    expect(find.text('Use MKV SeekHead Index'), findsOneWidget);
    expect(find.text('Max In-Memory Buffer'), findsOneWidget);
  });

  testWidgets('supported formats button lists MIME types', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // The button sits lower in the (scrollable) sidebar; make it visible.
    await tester.ensureVisible(find.textContaining('Supported formats:'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Supported formats:'));
    await tester.pumpAndSettle();

    // The dialog shows the title and contains at least one MIME type.
    expect(find.text('Supported Formats'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('Streams & Tracks card renders per-stream track info', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TracksCard(metadata: _metadataWithTracks()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Streams & Tracks (2)'), findsOneWidget);

    // One row per stream, typed and codec-labelled.
    expect(find.text('audio 1'), findsOneWidget);
    expect(find.text('video 2'), findsOneWidget);
    expect(find.text('Vorbis'), findsOneWidget);
    expect(find.text('theo'), findsOneWidget);

    // Audio details: sample rate, channels, samples, bitrate.
    expect(find.textContaining('Stream #1'), findsOneWidget);
    expect(find.textContaining('44.1 kHz'), findsOneWidget);
    expect(find.textContaining('2 ch'), findsOneWidget);
    expect(find.textContaining('16-bit'), findsOneWidget);
    expect(find.textContaining('544,000 samples'), findsOneWidget);
    expect(find.textContaining('128 kbps'), findsOneWidget);
    expect(find.textContaining('Lossy'), findsOneWidget);

    // Video details: resolution and frame rate.
    expect(find.textContaining('Stream #2'), findsOneWidget);
    expect(find.textContaining('640×480'), findsOneWidget);
    expect(find.textContaining('30.00 fps'), findsOneWidget);
  });

  testWidgets('TracksCard renders empty when no track info', (
    WidgetTester tester,
  ) async {
    final withoutTracks = AudioMetadata(
      format: const Format(container: 'mp3'),
      native: const {},
      common: _metadataWithTracks().common,
      quality: const QualityInformation(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TracksCard(metadata: withoutTracks)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TracksCard), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });

  test('common tag chips expose movement, podcast tvShow and play counter', () {
    final specs = buildCommonTagChipSpecs(_metadataWithTracks().common);
    final labels = specs.map((spec) => spec.$2).toList();

    expect(
      labels,
      containsAll([
        'Track 3/10',
        'Allegro (Movement 2/4)', // MVNM + MVIN combined
        'Storytime', // TV show
        'Podcast: podcast-123', // PCS/TGID/egid
        'Play count: 42', // PCNT
        'Peak 28000.0 / Avg 31000.0', // WMA PRIV levels
      ]),
    );
  });

  test('common tag chips omit missing optional fields', () {
    final specs = buildCommonTagChipSpecs(
      const CommonTags(
        track: TrackNo(),
        disk: TrackNo(),
        movementIndex: TrackNo(),
      ),
    );
    final labels = specs.map((spec) => spec.$2).toList();

    expect(labels, isEmpty);
  });

  testWidgets('demo URL presets fill the URL field', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Switch to the Remote URL tab where the presets live.
    await tester.tap(find.text('Remote URL'));
    await tester.pumpAndSettle();

    // Every preset is rendered, including the feature demos.
    for (final label in {
      'M4B (Chapters)',
      'MP3 (No Chapters)',
      'ASF (Track Info)',
      'ASF Audio+Video',
      'WMA (Rating/Levels)',
      'Ogg/Theora (Track Info)',
    }) {
      expect(find.text(label), findsOneWidget);
    }

    // Tapping a preset replaces the URL field contents with its URL.
    final oggPreset = find.text('Ogg/Theora (Track Info)');
    await tester.ensureVisible(oggPreset);
    await tester.pumpAndSettle();
    await tester.tap(oggPreset);
    await tester.pumpAndSettle();

    expect(find.textContaining('short.ogv'), findsOneWidget);
    expect(find.textContaining('test/samples/ogg'), findsOneWidget);
  });

  test('parseCustomRangeMs supports ms, seconds, and MM:SS / HH:MM:SS.mmm', () {
    expect(parseCustomRangeMs('0'), equals(0));
    expect(parseCustomRangeMs(' 15000 '), equals(15000));
    expect(parseCustomRangeMs('10,000'), equals(10000));
    expect(parseCustomRangeMs('25000ms'), equals(25000));
    expect(parseCustomRangeMs('12.5s'), equals(12500));
    expect(parseCustomRangeMs('01:30'), equals(90000));
    expect(parseCustomRangeMs('19:08:47.642'), equals(68927642));

    expect(parseCustomRangeMs(''), isNull);
    expect(parseCustomRangeMs('abc'), isNull);
    expect(parseCustomRangeMs('-5'), isNull);
    expect(parseCustomRangeMs('12.5'), isNull);
    expect(parseCustomRangeMs('01:75'), isNull);
  });

  testWidgets(
    'Download Custom Range requires a local file on Local tab and validates range',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      final downloadBtn = find.text('Download Custom Range');
      await tester.ensureVisible(downloadBtn);
      await tester.pumpAndSettle();
      await tester.tap(downloadBtn);
      await tester.pumpAndSettle();

      expect(
        find.text('Please select a local audio file first.'),
        findsOneWidget,
      );
      ScaffoldMessenger.of(
        tester.element(find.byType(DesktopScreen)),
      ).clearSnackBars();
      await tester.pumpAndSettle();

      // Switch to Remote URL tab to test range validation without launching FilePicker.
      await tester.ensureVisible(find.text('Remote URL'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remote URL'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Start (ms)'),
        'abc',
      );
      await tester.ensureVisible(downloadBtn);
      await tester.pumpAndSettle();
      await tester.tap(downloadBtn);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Invalid range. Enter ms (e.g. 15000), seconds with "s" (e.g. 15.5s), or HH:MM:SS.mmm.',
        ),
        findsOneWidget,
      );
      ScaffoldMessenger.of(
        tester.element(find.byType(DesktopScreen)),
      ).clearSnackBars();
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Start (ms)'),
        '10000',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'End (ms)'),
        '5000',
      );
      await tester.tap(downloadBtn);
      await tester.pumpAndSettle();

      expect(
        find.text('End time must be greater than Start time.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'WebAnalyzerScreen renders Chapters tab, header action, and Download Chapter buttons',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const metadataWithChapters = AudioMetadata(
        format: Format(
          container: 'mp4',
          codec: 'aac',
          duration: 60.0,
          chapters: [
            Chapter(title: 'Intro', start: 0, end: 15000),
            Chapter(
              title: 'Chapter 1: The Beginning',
              start: 15000,
              end: 45000,
            ),
            Chapter(title: 'Outro', start: 45000, end: 60000),
          ],
        ),
        native: {},
        common: CommonTags(
          title: 'Test Audiobook',
          artist: 'Author Name',
          album: 'Epic Story',
          track: TrackNo(),
          disk: TrackNo(),
          movementIndex: TrackNo(),
        ),
        quality: QualityInformation(),
      );

      final testFile = AnalyzedFile(
        name: 'audiobook.m4b',
        size: 1024 * 1024,
        bytes: Uint8List.fromList(List.filled(64, 0)),
      )..metadata = metadataWithChapters;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WebAnalyzerScreen(
              initialFiles: [testFile],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Header should show Download Chapters button and 3 Chapters chip
      expect(find.text('Download Chapters (3)'), findsOneWidget);
      expect(find.text('3 Chapters'), findsOneWidget);

      // 2. Tab Bar should show Chapters (3) tab
      expect(find.text('Chapters (3)'), findsOneWidget);

      // 3. Overview Tab should show CHAPTERS & SLICING (3) card
      expect(find.text('CHAPTERS & SLICING (3)'), findsOneWidget);
      expect(find.text('Intro'), findsOneWidget);
      expect(find.text('Chapter 1: The Beginning'), findsOneWidget);

      // 4. Download buttons on overview
      expect(find.text('Download'), findsWidgets);

      // 5. Tap Chapters (3) Tab
      await tester.tap(find.text('Chapters (3)'));
      await tester.pumpAndSettle();

      // 6. Dedicated Chapters Tab view content
      expect(find.text('Audiobook Chapters & Slicing'), findsOneWidget);
      expect(find.text('Download Range'), findsOneWidget);
      expect(find.text('Outro'), findsOneWidget);
      expect(find.text('Download'), findsWidgets);
    },
  );
}
