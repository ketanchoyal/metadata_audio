library;

import 'package:metadata_audio/src/model/types.dart';

Future<AudioMetadata> parseWebFile(Object file, {ParseOptions? options}) {
  throw UnsupportedError(
    'parseWebFile is only supported on web. Use parseFile on IO platforms.',
  );
}
