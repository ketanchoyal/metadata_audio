import 'dart:io';
import 'dart:math' as math;

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/native/api.dart' as native;
import 'package:metadata_audio/src/native/frb_generated.dart';

class BenchmarkCase {
  const BenchmarkCase({
    required this.name,
    required this.relativePath,
    required this.iterations,
    this.warmup = 5,
  });

  final String name;
  final String relativePath;
  final int iterations;
  final int warmup;
}

class BackendStats {
  const BackendStats({required this.durationsUs});

  final List<int> durationsUs;

  int get runs => durationsUs.length;

  double get meanMs =>
      durationsUs.reduce((a, b) => a + b) / durationsUs.length / 1000.0;

  double get minMs => durationsUs.reduce(math.min) / 1000.0;

  double get maxMs => durationsUs.reduce(math.max) / 1000.0;

  double percentileMs(double p) {
    final sorted = [...durationsUs]..sort();
    final index = (p * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
    return sorted[index] / 1000.0;
  }
}

class ComparativeResult {
  const ComparativeResult({required this.dartStats, required this.rustStats});

  final BackendStats dartStats;
  final BackendStats rustStats;
}

ParserFactory _buildPureDartFactory() {
  final registry = ParserRegistry()
    ..register(FlacLoader())
    ..register(Mp4Loader())
    ..register(OggLoader())
    ..register(WaveLoader())
    ..register(AiffLoader())
    ..register(AsfLoader())
    ..register(Apev2Loader())
    ..register(MatroskaLoader())
    ..register(MusepackLoader())
    ..register(WavPackLoader())
    ..register(DsfLoader())
    ..register(DsdiffLoader())
    ..register(Id3v2Loader())
    ..register(MpegLoader());

  return ParserFactory(registry);
}

Future<void> _parseWithDart(String path, ParserFactory factory) async {
  final tokenizer = FileTokenizer.fromPath(path);
  try {
    await parseFromTokenizerWithFactory(
      tokenizer,
      factory,
      options: const ParseOptions(includeChapters: true),
    );
  } finally {
    tokenizer.close();
  }
}

Future<void> _parseWithRust(String path) async {
  await native.parseFromPath(path: path);
}

Future<ComparativeResult> _runComparativeCase(
  String absolutePath,
  BenchmarkCase benchmark,
  ParserFactory pureFactory,
) async {
  final dartDurationsUs = <int>[];
  final rustDurationsUs = <int>[];

  for (var i = 0; i < benchmark.warmup; i++) {
    final dartFirst = i.isEven;
    if (dartFirst) {
      await _parseWithDart(absolutePath, pureFactory);
      await _parseWithRust(absolutePath);
    } else {
      await _parseWithRust(absolutePath);
      await _parseWithDart(absolutePath, pureFactory);
    }
  }

  for (var i = 0; i < benchmark.iterations; i++) {
    final dartFirst = i.isEven;

    if (dartFirst) {
      final dartSw = Stopwatch()..start();
      await _parseWithDart(absolutePath, pureFactory);
      dartSw.stop();
      dartDurationsUs.add(dartSw.elapsedMicroseconds);

      final rustSw = Stopwatch()..start();
      await _parseWithRust(absolutePath);
      rustSw.stop();
      rustDurationsUs.add(rustSw.elapsedMicroseconds);
    } else {
      final rustSw = Stopwatch()..start();
      await _parseWithRust(absolutePath);
      rustSw.stop();
      rustDurationsUs.add(rustSw.elapsedMicroseconds);

      final dartSw = Stopwatch()..start();
      await _parseWithDart(absolutePath, pureFactory);
      dartSw.stop();
      dartDurationsUs.add(dartSw.elapsedMicroseconds);
    }
  }

  return ComparativeResult(
    dartStats: BackendStats(durationsUs: dartDurationsUs),
    rustStats: BackendStats(durationsUs: rustDurationsUs),
  );
}

String _fmt(double value) => value.toStringAsFixed(3);

Future<void> main() async {
  final root = Directory.current.path;
  final pureFactory = _buildPureDartFactory();

  final cases = <BenchmarkCase>[
    const BenchmarkCase(
      name: 'MP3 small (id3v2.3)',
      relativePath: 'test/samples/mp3/id3v2.3.mp3',
      iterations: 60,
      warmup: 8,
    ),
    const BenchmarkCase(
      name: 'FLAC small (sample)',
      relativePath: 'test/samples/flac/sample.flac',
      iterations: 60,
      warmup: 8,
    ),
    const BenchmarkCase(
      name: 'OGG small (vorbis)',
      relativePath: 'test/samples/ogg/vorbis.ogg',
      iterations: 60,
      warmup: 8,
    ),
    const BenchmarkCase(
      name: 'MP4 small (sample)',
      relativePath: 'test/samples/mp4/sample.m4a',
      iterations: 60,
      warmup: 8,
    ),
    const BenchmarkCase(
      name: 'MP4 large (The Dark Forest)',
      relativePath: 'test/samples/mp4/The Dark Forest.m4a',
      iterations: 8,
      warmup: 2,
    ),
  ];

  await RustLib.init();

  final results = <BenchmarkCase, ComparativeResult>{};

  try {
    for (final benchmark in cases) {
      final absolutePath = '$root/${benchmark.relativePath}';
      final file = File(absolutePath);
      if (!file.existsSync()) {
        stderr.writeln('Skipping ${benchmark.name}: missing file $absolutePath');
        continue;
      }

      stdout.writeln(
        'Running ${benchmark.name} | iterations=${benchmark.iterations}, warmup=${benchmark.warmup}',
      );

      final comparative = await _runComparativeCase(
        absolutePath,
        benchmark,
        pureFactory,
      );
      results[benchmark] = comparative;
    }
  } finally {
    RustLib.dispose();
  }

  if (results.isEmpty) {
    stderr.writeln('No benchmark cases were executed.');
    exitCode = 1;
    return;
  }

  stdout.writeln('\n=== Rust vs Dart backend benchmark (lower is better, ms) ===');
  stdout.writeln(
    'Case | Backend | mean | p50 | p95 | min | max | runs | speedup(vs Dart mean)',
  );

  double dartMeanAccumulator = 0;
  double rustMeanAccumulator = 0;
  var caseCount = 0;

  for (final entry in results.entries) {
    final benchmark = entry.key;
    final comparative = entry.value;
    final dartStats = comparative.dartStats;
    final rustStats = comparative.rustStats;
    final speedup = dartStats.meanMs / rustStats.meanMs;

    dartMeanAccumulator += dartStats.meanMs;
    rustMeanAccumulator += rustStats.meanMs;
    caseCount++;

    stdout.writeln(
      '${benchmark.name} | Dart | ${_fmt(dartStats.meanMs)} | ${_fmt(dartStats.percentileMs(0.5))} | ${_fmt(dartStats.percentileMs(0.95))} | ${_fmt(dartStats.minMs)} | ${_fmt(dartStats.maxMs)} | ${dartStats.runs} | 1.000x',
    );
    stdout.writeln(
      '${benchmark.name} | Rust | ${_fmt(rustStats.meanMs)} | ${_fmt(rustStats.percentileMs(0.5))} | ${_fmt(rustStats.percentileMs(0.95))} | ${_fmt(rustStats.minMs)} | ${_fmt(rustStats.maxMs)} | ${rustStats.runs} | ${_fmt(speedup)}x',
    );
  }

  final avgDartMean = dartMeanAccumulator / caseCount;
  final avgRustMean = rustMeanAccumulator / caseCount;
  final overallSpeedup = avgDartMean / avgRustMean;

  stdout.writeln('\n=== Aggregate (unweighted mean across cases) ===');
  stdout.writeln('Dart mean(ms): ${_fmt(avgDartMean)}');
  stdout.writeln('Rust mean(ms): ${_fmt(avgRustMean)}');
  stdout.writeln('Rust speedup: ${_fmt(overallSpeedup)}x');
}
