library;

// ignore_for_file: public_member_api_docs

import 'package:metadata_audio/src/parse_error.dart';

class MusepackContentError extends UnexpectedFileContentError {
  MusepackContentError(String message) : super('Musepack', message);
}
