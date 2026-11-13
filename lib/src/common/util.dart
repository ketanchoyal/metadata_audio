/// Shared value conversions used by tag mappers and the metadata collector.
library;

import 'dart:math' as math;

import 'package:metadata_audio/src/model/types.dart';

/// Convert decibels to a linear ratio: `10^(dB / 20)`.
double dbToRatio(double dB) => math.pow(10.0, dB / 20.0).toDouble();

/// Convert a linear ratio to decibels: `20 * log10(ratio)`.
double ratioToDb(double ratio) => 20.0 * math.log(ratio) / math.ln10;

/// Parses a string holding a ratio like `'0.034'` or `'-7.54 dB'` into a
/// [Ratio].
///
/// Returns `null` when the numeric part cannot be parsed or is invalid. When the
/// value does not carry a `dB` suffix the [Ratio.dB] field stays `null`.
Ratio? toRatio(String value) {
  final match = RegExp(
    r'^([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?)\s*(dB)?$',
    caseSensitive: false,
  ).firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  final number = double.tryParse(match.group(1)!);
  if (number == null || !number.isFinite) {
    return null;
  }
  final isDb = match.group(2) != null;
  final ratio = isDb ? dbToRatio(number) : number;
  if (!ratio.isFinite || ratio < 0) {
    return null;
  }
  return isDb ? Ratio(ratio: ratio, dB: number) : Ratio(ratio: ratio);
}
