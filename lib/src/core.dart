/// Core API for audio metadata parsing.
///
/// Provides platform-agnostic functions: [parseBytes], [parseStream],
/// [parseFromTokenizer], and utility functions.
///
/// Platform-specific functions are provided via conditional imports:
/// - [parseFile]: IO platforms use dart:io; web throws [UnsupportedError]
/// - [parseWebFile]: Web platforms accept browser File objects; IO throws [UnsupportedError]
library;

// Re-export all implementation from core_impl
export 'core_impl.dart';

// Conditionally export parseFile based on platform
export 'parse_file_io.dart' if (dart.library.html) 'parse_file_web.dart';

// Conditionally export parseWebFile based on platform
// On IO: throws UnsupportedError (browser File objects don't exist)
// On web: reads web.File into bytes and delegates to parseBytes
export 'parse_web_file_io.dart' if (dart.library.html) 'parse_web_file_web.dart';
