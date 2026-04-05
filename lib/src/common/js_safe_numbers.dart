library;

/// Largest integer that is exactly representable in JavaScript.
const int maxSafeJsInt = 9007199254740991;

/// Largest signed 64-bit integer, parsed without using a JS-unsafe literal.
final BigInt maxSignedInt64 = BigInt.parse('9223372036854775807');
