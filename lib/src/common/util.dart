/// Shared value conversions used by tag mappers and the metadata collector.
///
/// Mirrors the helpers from upstream `lib/common/Util.ts` from
/// Borewit/music-metadata.
library;

import 'dart:math' as math;

import '../model/types.dart';

/// Convert decibels to a linear ratio.
///
/// Mirrors upstream `dbToRatio`: `10^(dB / 20)`.
double dbToRatio(double dB) => math.pow(10.0, dB / 20.0).toDouble();

/// Convert a linear ratio to decibels.
///
/// Mirrors upstream `ratioToDb`: `20 * log10(ratio)`.
double ratioToDb(double ratio) => 20.0 * math.log(ratio) / math.ln10;

/// Parses a string holding a ratio like `'0.034'` or `'-7.54 dB'` into a
/// [Ratio].
///
/// Mirrors upstream `toRatio`. Returns `null` when the numeric part cannot be
/// parsed (upstream produces `NaN` values, which its callers reject). When the
/// value does not carry a `dB` suffix the [Ratio.dB] field stays `null`, like
/// upstream's `undefined`.
Ratio? toRatio(String value) {
  final limited = _splitLimit(value, ' ', 2);
  if (limited.isEmpty) {
    return null;
  }
  final dBPart = limited.length == 2 && limited[1].trim().toLowerCase() == 'db';
  final v = double.tryParse(limited[0].trim());
  if (v == null) {
    return null;
  }
  return dBPart ? Ratio(ratio: dbToRatio(v), dB: v) : Ratio(ratio: v);
}

/// Splits [text] on [separator], returning at most [limit] segments where
/// [limit] is the maximum number of segments (the final segment keeps any
/// remaining text, separator included).
///
/// Mirrors the JavaScript `String.prototype.split(separator, limit)` semantics
/// used by upstream hardening fixes (`split(' ', 2)`).
List<String> _splitLimit(String text, String pattern, int limit) {
  if (limit <= 0) {
    return const <String>[];
  }
  final result = <String>[];
  var start = 0;
  while (result.length < limit - 1) {
    final index = text.indexOf(pattern, start);
    if (index == -1) {
      break;
    }
    result.add(text.substring(start, index));
    start = index + pattern.length;
  }
  result.add(text.substring(start));
  return result;
}
