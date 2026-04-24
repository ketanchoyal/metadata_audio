import 'dart:io';
import 'dart:math' as math;

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/core.dart';
import 'package:metadata_audio/src/native/api.dart' as native;
import 'package:metadata_audio/src/native/frb_generated.dart';

class RemoteBenchmarkCase {
  const RemoteBenchmarkCase({required this.name, required this.url});

  final String name;
  final String url;
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
  const ComparativeResult({
    required this.dartStats,
    required this.rustStats,
    required this.dartChapterCount,
    required this.rustChapterCount,
    required this.strategyInfo,
  });

  final BackendStats dartStats;
  final BackendStats rustStats;
  final int dartChapterCount;
  final int rustChapterCount;
  final StrategyInfo strategyInfo;
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

Future<AudioMetadata> _parseUrlWithDartOnly(
  String url,
  StrategyInfo info,
  ParserFactory factory,
  Duration timeout,
) async {
  final options = const ParseOptions(includeChapters: true);

  switch (info.strategy) {
    case ParseStrategy.fullDownload:
      final tokenizer = await HttpTokenizer.fromUrl(url, timeout: timeout);
      try {
        return await parseFromTokenizerWithFactory(
          tokenizer,
          factory,
          options: options,
        );
      } finally {
        tokenizer.close();
      }

    case ParseStrategy.headerOnly:
      final tokenizer = await RangeTokenizer.fromUrl(url, timeout: timeout);
      try {
        return await parseFromTokenizerWithFactory(
          tokenizer,
          factory,
          options: options,
        );
      } finally {
        tokenizer.close();
      }

    case ParseStrategy.probe:
      final tokenizer = await ProbingRangeTokenizer.fromUrl(
        url,
        timeout: timeout,
        probeStrategy: info.probeStrategy,
      );
      try {
        return await parseFromTokenizerWithFactory(
          tokenizer,
          factory,
          options: options,
        );
      } finally {
        tokenizer.close();
      }

    case ParseStrategy.randomAccess:
      final tokenizer = await RandomAccessTokenizer.fromUrl(
        url,
        timeout: timeout,
      );
      final totalSize = tokenizer.totalSize;
      try {
        await tokenizer.prefetchRange(0, 262144);
        if (totalSize != null && totalSize > 0) {
          final tailSize = totalSize < 16 * 1024 * 1024
              ? totalSize
              : 16 * 1024 * 1024;
          final tailStart = totalSize - tailSize;
          await tokenizer.prefetchRange(tailStart, totalSize);
        }
        return await parseFromTokenizerWithFactory(
          tokenizer,
          factory,
          options: options,
        );
      } finally {
        tokenizer.close();
      }
  }
}

Future<int> _parseWithRust(String url, Duration timeout) async {
  final info = await detectStrategy(url, timeout: timeout);
  final chapters = await native.parseChaptersFromUrl(
    url: url,
    timeoutMs: BigInt.from(timeout.inMilliseconds),
    fileSizeHint: info.fileSize != null ? BigInt.from(info.fileSize!) : null,
  );
  return chapters.length;
}

Future<ComparativeResult> _runComparativeCase(
  RemoteBenchmarkCase benchmark,
  ParserFactory pureFactory, {
  required int warmup,
  required int iterations,
  required Duration timeout,
}) async {
  final strategyInfo = await detectStrategy(benchmark.url, timeout: timeout);
  final dartDurationsUs = <int>[];
  final rustDurationsUs = <int>[];

  for (var i = 0; i < warmup; i++) {
    final dartFirst = i.isEven;
    if (dartFirst) {
      await _parseUrlWithDartOnly(benchmark.url, strategyInfo, pureFactory, timeout);
      await _parseWithRust(benchmark.url, timeout);
    } else {
      await _parseWithRust(benchmark.url, timeout);
      await _parseUrlWithDartOnly(benchmark.url, strategyInfo, pureFactory, timeout);
    }
  }

  late final int dartChapterCount;
  late final int rustChapterCount;

  for (var i = 0; i < iterations; i++) {
    final dartFirst = i.isEven;

    if (dartFirst) {
      final dartSw = Stopwatch()..start();
      final metadata = await _parseUrlWithDartOnly(
        benchmark.url,
        strategyInfo,
        pureFactory,
        timeout,
      );
      dartSw.stop();
      dartDurationsUs.add(dartSw.elapsedMicroseconds);

      final rustSw = Stopwatch()..start();
      final rustCount = await _parseWithRust(benchmark.url, timeout);
      rustSw.stop();
      rustDurationsUs.add(rustSw.elapsedMicroseconds);

      if (i == 0) {
        dartChapterCount = metadata.format.chapters?.length ?? 0;
        rustChapterCount = rustCount;
      }
    } else {
      final rustSw = Stopwatch()..start();
      final rustCount = await _parseWithRust(benchmark.url, timeout);
      rustSw.stop();
      rustDurationsUs.add(rustSw.elapsedMicroseconds);

      final dartSw = Stopwatch()..start();
      final metadata = await _parseUrlWithDartOnly(
        benchmark.url,
        strategyInfo,
        pureFactory,
        timeout,
      );
      dartSw.stop();
      dartDurationsUs.add(dartSw.elapsedMicroseconds);

      if (i == 0) {
        dartChapterCount = metadata.format.chapters?.length ?? 0;
        rustChapterCount = rustCount;
      }
    }
  }

  return ComparativeResult(
    dartStats: BackendStats(durationsUs: dartDurationsUs),
    rustStats: BackendStats(durationsUs: rustDurationsUs),
    dartChapterCount: dartChapterCount,
    rustChapterCount: rustChapterCount,
    strategyInfo: strategyInfo,
  );
}

String _fmt(double value) => value.toStringAsFixed(3);

List<RemoteBenchmarkCase> _parseCases(List<String> arguments) {
  final urls = <String>[];
  for (var i = 0; i < arguments.length; i++) {
    final arg = arguments[i];
    if (arg == '--url' && i + 1 < arguments.length) {
      urls.add(arguments[++i]);
      continue;
    }
    if (arg.startsWith('--url=')) {
      urls.add(arg.substring('--url='.length));
    }
  }

  if (urls.isEmpty) {
    for (final key in ['METADATA_AUDIO_BENCH_URL_1', 'METADATA_AUDIO_BENCH_URL_2']) {
      final value = Platform.environment[key];
      if (value != null && value.trim().isNotEmpty) {
        urls.add(value.trim());
      }
    }
  }

  return [
    for (var index = 0; index < urls.length; index++)
      RemoteBenchmarkCase(name: 'Remote URL #${index + 1}', url: urls[index]),
  ];
}

int _parseIntArg(List<String> arguments, String name, int defaultValue) {
  for (var i = 0; i < arguments.length; i++) {
    final arg = arguments[i];
    if (arg == '--$name' && i + 1 < arguments.length) {
      return int.tryParse(arguments[i + 1]) ?? defaultValue;
    }
    if (arg.startsWith('--$name=')) {
      return int.tryParse(arg.substring(name.length + 3)) ?? defaultValue;
    }
  }
  return defaultValue;
}

String _usage() => '''
Usage:
  dart run tool/benchmark_remote_url_rust_vs_dart.dart --url <url1> --url <url2>

Options:
  --url <value>              Repeat for each benchmark URL.
  --iterations <count>       Timed runs per URL (default: 3).
  --warmup <count>           Warmup runs per URL (default: 1).
  --timeout-seconds <count>  Timeout budget per parse call (default: 120).

Environment fallback:
  METADATA_AUDIO_BENCH_URL_1
  METADATA_AUDIO_BENCH_URL_2
''';

Future<void> main(List<String> arguments) async {
  final cases = _parseCases(arguments);
  if (cases.isEmpty) {
    stderr.writeln(_usage());
    exitCode = 64;
    return;
  }

  final iterations = _parseIntArg(arguments, 'iterations', 3);
  final warmup = _parseIntArg(arguments, 'warmup', 1);
  final timeoutSeconds = _parseIntArg(arguments, 'timeout-seconds', 120);
  final timeout = Duration(seconds: timeoutSeconds);
  final pureFactory = _buildPureDartFactory();

  await RustLib.init();

  try {
    final results = <RemoteBenchmarkCase, ComparativeResult>{};
    for (final benchmark in cases) {
      stdout.writeln(
        'Running ${benchmark.name} | iterations=$iterations, warmup=$warmup, timeout=${timeout.inSeconds}s',
      );
      results[benchmark] = await _runComparativeCase(
        benchmark,
        pureFactory,
        warmup: warmup,
        iterations: iterations,
        timeout: timeout,
      );
    }

    stdout.writeln('\n=== Remote Rust vs Dart URL benchmark (lower is better, ms) ===');
    stdout.writeln(
      'Case | Strategy | Dart mean | Rust mean | Dart p95 | Rust p95 | Dart chapters | Rust chapters | Rust speedup',
    );

    for (final entry in results.entries) {
      final benchmark = entry.key;
      final result = entry.value;
      final speedup = result.dartStats.meanMs / result.rustStats.meanMs;
      stdout.writeln(
        '${benchmark.name} | ${result.strategyInfo.strategy} | ${_fmt(result.dartStats.meanMs)} | ${_fmt(result.rustStats.meanMs)} | ${_fmt(result.dartStats.percentileMs(0.95))} | ${_fmt(result.rustStats.percentileMs(0.95))} | ${result.dartChapterCount} | ${result.rustChapterCount} | ${_fmt(speedup)}x',
      );
    }
  } finally {
    RustLib.dispose();
  }
}
