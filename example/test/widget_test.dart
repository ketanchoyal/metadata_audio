// Smoke test for the example app shell.
//
// Verifies the main layout renders: the sidebar header, the Local/Remote
// tabs, the parser configuration switches, plus the Streams & Tracks card
// and the common-tag chips builders.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';
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
      const CommonTags(track: TrackNo(), disk: TrackNo(), movementIndex: TrackNo()),
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
    expect(
      find.textContaining('music-metadata/master/test/samples/ogg'),
      findsOneWidget,
    );
  });
}
