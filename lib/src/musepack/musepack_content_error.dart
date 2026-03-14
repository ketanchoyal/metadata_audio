library;

// ignore_for_file: public_member_api_docs

import 'package:audio_metadata/src/parse_error.dart';

class MusepackContentError extends UnexpectedFileContentError {
  MusepackContentError(String message) : super('Musepack', message);
}
