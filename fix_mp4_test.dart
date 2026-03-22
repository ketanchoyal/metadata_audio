import 'dart:io';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:path/path.dart' as p;

void main() async {
  final file = File(p.join('test', 'samples', 'mp4', 'sample.m4a'));
  final metadata = await parseFile(
    file.path,
    options: const ParseOptions(includeChapters: true),
  );

  print('Chapters: ${metadata.format.chapters?.length}');
  for (final chapter in metadata.format.chapters ?? <Chapter>[]) {
    print('Title: ${chapter.title}, Start: ${chapter.start}, End: ${chapter.end}');
  }
}
