/// ID3v1 parser for reading ID3v1 metadata tags.
///
/// Reads the last 128 bytes of an audio file looking for ID3v1 tag structure.
/// ID3v1 is a simple, fixed-format tag appended to the end of files.
///
/// Spec: http://id3.org/ID3v1
/// Wiki: https://en.wikipedia.org/wiki/ID3
///
/// Based on upstream: https://github.com/Borewit/music-metadata/blob/master/lib/id3v1/ID3v1Parser.ts
library;

import 'dart:convert';

import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

/// Standard ID3v1 genres (0-255).
///
/// Maps genre byte values to genre names according to the ID3v1 specification.
/// Ref: https://en.wikipedia.org/wiki/ID3_(metadata)#ID3v1_genres
const genres = [
  'Blues',
  'Classic Rock',
  'Country',
  'Dance',
  'Disco',
  'Funk',
  'Grunge',
  'Hip-Hop',
  'Jazz',
  'Metal',
  'New Age',
  'Oldies',
  'Other',
  'Pop',
  'R&B',
  'Rap',
  'Reggae',
  'Rock',
  'Techno',
  'Industrial',
  'Alternative',
  'Ska',
  'Death Metal',
  'Pranks',
  'Soundtrack',
  'Euro-Techno',
  'Ambient',
  'Trip-Hop',
  'Vocal',
  'Jazz+Funk',
  'Fusion',
  'Trance',
  'Classical',
  'Instrumental',
  'Acid',
  'House',
  'Game',
  'Sound Clip',
  'Gospel',
  'Noise',
  'Alt. Rock',
  'Bass',
  'Soul',
  'Punk',
  'Space',
  'Meditative',
  'Instrumental Pop',
  'Instrumental Rock',
  'Ethnic',
  'Gothic',
  'Darkwave',
  'Techno-Industrial',
  'Electronic',
  'Pop-Folk',
  'Eurodance',
  'Dream',
  'Southern Rock',
  'Comedy',
  'Cult',
  'Gangsta Rap',
  'Top 40',
  'Christian Rap',
  'Pop/Funk',
  'Jungle',
  'Native American',
  'Cabaret',
  'New Wave',
  'Psychedelic',
  'Rave',
  'Showtunes',
  'Trailer',
  'Lo-Fi',
  'Tribal',
  'Acid Punk',
  'Acid Jazz',
  'Polka',
  'Retro',
  'Musical',
  'Rock & Roll',
  'Hard Rock',
  'Folk',
  'Folk/Rock',
  'National Folk',
  'Swing',
  'Fast-Fusion',
  'Bebob',
  'Latin',
  'Revival',
  'Celtic',
  'Bluegrass',
  'Avantgarde',
  'Gothic Rock',
  'Progressive Rock',
  'Psychedelic Rock',
  'Symphonic Rock',
  'Slow Rock',
  'Big Band',
  'Chorus',
  'Easy Listening',
  'Acoustic',
  'Humour',
  'Speech',
  'Chanson',
  'Opera',
  'Chamber Music',
  'Sonata',
  'Symphony',
  'Booty Bass',
  'Primus',
  'Porn Groove',
  'Satire',
  'Slow Jam',
  'Club',
  'Tango',
  'Samba',
  'Folklore',
  'Ballad',
  'Power Ballad',
  'Rhythmic Soul',
  'Freestyle',
  'Duet',
  'Punk Rock',
  'Drum Solo',
  'A Cappella',
  'Euro-House',
  'Dance Hall',
  'Goa',
  'Drum & Bass',
  'Club-House',
  'Hardcore',
  'Terror',
  'Indie',
  'BritPop',
  'Negerpunk',
  'Polsk Punk',
  'Beat',
  'Christian Gangsta Rap',
  'Heavy Metal',
  'Black Metal',
  'Crossover',
  'Contemporary Christian',
  'Christian Rock',
  'Merengue',
  'Salsa',
  'Thrash Metal',
  'Anime',
  'JPop',
  'Synthpop',
  'Abstract',
  'Art Rock',
  'Baroque',
  'Bhangra',
  'Big Beat',
  'Breakbeat',
  'Chillout',
  'Downtempo',
  'Dub',
  'EBM',
  'Eclectic',
  'Electro',
  'Electroclash',
  'Emo',
  'Experimental',
  'Garage',
  'Global',
  'IDM',
  'Illbient',
  'Industro-Goth',
  'Jam Band',
  'Krautrock',
  'Leftfield',
  'Lounge',
  'Math Rock',
  'New Romantic',
  'Nu-Breakz',
  'Post-Punk',
  'Post-Rock',
  'Psytrance',
  'Shoegaze',
  'Space Rock',
  'Trop Rock',
  'World Music',
  'Neoclassical',
  'Audiobook',
  'Audio Theatre',
  'Neue Deutsche Welle',
  'Podcast',
  'Indie Rock',
  'G-Funk',
  'Dubstep',
  'Garage Rock',
  'Psybient',
];

/// ID3v1 tag structure representation.
///
/// Contains parsed ID3v1 tag data from a 128-byte block.
class _Id3v1Header {
  _Id3v1Header({
    required this.header,
    required this.zeroByte,
    required this.track,
    required this.genre,
    this.title,
    this.artist,
    this.album,
    this.year,
    this.comment,
  });
  final String header;
  final String? title;
  final String? artist;
  final String? album;
  final String? year;
  final String? comment;
  final int zeroByte;
  final int track;
  final int genre;
}

/// Parser for ID3v1 metadata tags.
///
/// ID3v1 is a 128-byte fixed-format tag appended to the end of audio files.
/// This parser seeks to the last 128 bytes and reads the tag structure if present.
///
/// Structure (128 bytes total):
/// - Bytes 0-2: "TAG" header (3 bytes)
/// - Bytes 3-32: Title (30 bytes, latin1)
/// - Bytes 33-62: Artist (30 bytes, latin1)
/// - Bytes 63-92: Album (30 bytes, latin1)
/// - Bytes 93-96: Year (4 bytes, latin1)
/// - Bytes 97-126: Comment (30 bytes in v1, 28 bytes in v1.1)
/// - Bytes 125-126: Track number (ID3v1.1 only), stored as: [0, track_number]
/// - Byte 127: Genre (1 byte, unsigned)
class Id3v1Parser {
  /// Create an ID3v1Parser.
  Id3v1Parser({required this.metadata, required this.tokenizer});
  static const int id3v1Size = 128;
  static const String id3v1Header = 'TAG';

  final MetadataCollector metadata;
  final Tokenizer tokenizer;

  /// Parse ID3v1 tag from tokenizer.
  ///
  /// Seeks to the last 128 bytes of the file, reads the ID3v1 tag structure,
  /// and adds parsed tags to the metadata collector.
  ///
  /// Returns true if a valid ID3v1 tag was found and parsed, false otherwise.
  Future<bool> parse() async {
    final fileInfo = tokenizer.fileInfo;

    // Can't parse without file size
    if (fileInfo == null || fileInfo.size == null) {
      return false;
    }

    // File must be at least 128 bytes to contain ID3v1 tag
    if (fileInfo.size! < id3v1Size) {
      return false;
    }

    final offset = fileInfo.size! - id3v1Size;
    try {
      if (tokenizer.canSeek) {
        tokenizer.seek(offset);
      } else if (tokenizer.position > offset) {
        return false;
      }

      // Read the 128-byte ID3v1 block
      final block = tokenizer.readBytes(id3v1Size);

      // Parse the block
      final header = _parseId3v1Block(block);
      if (header == null) {
        return false;
      }

      // Add parsed tags to metadata
      if (header.title != null) {
        metadata.addNativeTag('ID3v1', 'title', header.title);
      }
      if (header.artist != null) {
        metadata.addNativeTag('ID3v1', 'artist', header.artist);
      }
      if (header.album != null) {
        metadata.addNativeTag('ID3v1', 'album', header.album);
      }
      if (header.year != null) {
        metadata.addNativeTag('ID3v1', 'year', header.year);
      }
      if (header.comment != null) {
        metadata.addNativeTag('ID3v1', 'comment', header.comment);
      }
      if (header.track > 0) {
        metadata.addNativeTag('ID3v1', 'track', header.track);
      }
      // Only add genre if it's not 0 (which maps to 'Blues' but is often unused)
      if (header.genre > 0) {
        final genreName = _getGenre(header.genre);
        if (genreName != null) {
          metadata.addNativeTag('ID3v1', 'genre', genreName);
        }
      }

      return true;
    } on TokenizerException {
      // Data not available (e.g., with ProbingRangeTokenizer)
      return false;
    }
  }

  /// Parse a 128-byte ID3v1 block.
  ///
  /// Returns an _Id3v1Header if the block starts with "TAG", null otherwise.
  static _Id3v1Header? _parseId3v1Block(List<int> block) {
    if (block.length != id3v1Size) {
      return null;
    }

    // Check for "TAG" header
    final headerBytes = block.sublist(0, 3);
    final header = latin1.decode(headerBytes);
    if (header != id3v1Header) {
      return null;
    }

    // Parse fixed-width fields, trimming null bytes and whitespace
    final title = _parseStringField(block, 3, 30);
    final artist = _parseStringField(block, 33, 30);
    final album = _parseStringField(block, 63, 30);
    final year = _parseStringField(block, 93, 4);

    // ID3v1.1 has track number in bytes 125-126
    // Byte 125 is a null byte separator, byte 126 is the track number
    final zeroByte = block[125];
    var track = 0;
    if (zeroByte == 0 && block[126] != 0) {
      // ID3v1.1 format with track number
      track = block[126];
      // Comment is only 28 bytes in ID3v1.1 (not 30)
    }

    // Parse comment (28 or 30 bytes depending on ID3v1 version)
    final commentLength = (track > 0) ? 28 : 30;
    final comment = _parseStringField(block, 97, commentLength);

    // Genre byte at offset 127
    final genre = block[127];

    return _Id3v1Header(
      header: header,
      title: title,
      artist: artist,
      album: album,
      year: year,
      comment: comment,
      zeroByte: zeroByte,
      track: track,
      genre: genre,
    );
  }

  /// Parse a fixed-width string field, trimming null bytes and whitespace.
  ///
  /// Reads [length] bytes starting at [offset], decodes as latin1,
  /// and trims null bytes and whitespace. Returns null if empty after trimming.
  static String? _parseStringField(List<int> block, int offset, int length) {
    if (offset + length > block.length) {
      return null;
    }

    final bytes = block.sublist(offset, offset + length);

    // Find the first null byte (string terminator in ID3v1)
    var endIndex = bytes.length;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0) {
        endIndex = i;
        break;
      }
    }

    final stringBytes = bytes.sublist(0, endIndex);
    if (stringBytes.isEmpty) {
      return null;
    }

    try {
      final value = latin1.decode(stringBytes).trim();
      return value.isEmpty ? null : value;
    } catch (e) {
      return null;
    }
  }

  /// Get genre name from genre byte index.
  ///
  /// Returns the genre name for a valid genre index, null otherwise.
  static String? _getGenre(int genreIndex) {
    if (genreIndex >= 0 && genreIndex < genres.length) {
      return genres[genreIndex];
    }
    return null;
  }
}
