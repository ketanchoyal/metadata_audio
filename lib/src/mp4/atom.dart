library;

import 'package:metadata_audio/src/mp4/atom_token.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

typedef AtomDataHandler =
    Future<void> Function(Mp4Atom atom, int payloadLength);

typedef AtomPrefetchRange = Future<void> Function(int start, int end);

class Mp4Atom {
  Mp4Atom({
    required this.header,
    required this.parent,
    required this.offset,
    required this.payloadLength,
  }) : atomPath = (parent != null ? '${parent.atomPath}.' : '') + header.name;

  final AtomHeader header;
  final Mp4Atom? parent;
  final int offset;
  final int payloadLength;
  final String atomPath;
  final List<Mp4Atom> children = <Mp4Atom>[];

  static const Set<String> _containerAtoms = <String>{
    'moov',
    'trak',
    'mdia',
    'minf',
    'stbl',
    'udta',
    'meta',
    'ilst',
    'moof',
    'traf',
    'tref',
    '<id>',
  };

  bool get isContainer => _containerAtoms.contains(header.name);

  static Future<Mp4Atom> readAtom(
    Tokenizer tokenizer,
    AtomDataHandler dataHandler,
    Mp4Atom? parent,
    int remaining, {
    AtomPrefetchRange? prefetchRange,
  }) async {
    final offset = tokenizer.position;

    if (prefetchRange != null && remaining > 0) {
      final headerRead = remaining < 16 ? remaining : 16;
      await prefetchRange(offset, offset + headerRead);
    }

    final baseHeader = tokenizer.readBytes(AtomToken.headerLength);
    var header = AtomToken.parseHeader(baseHeader);
    if (header.length == 1) {
      final extended = tokenizer.readBytes(8);
      header = AtomToken.parseHeaderWithExtendedSize(<int>[
        ...baseHeader,
        ...extended,
      ]);
    }

    final computedPayloadLength = _resolvePayloadLength(
      header: header,
      remaining: remaining,
    );

    final atom = Mp4Atom(
      header: header,
      parent: parent,
      offset: offset,
      payloadLength: computedPayloadLength,
    );

    await atom._readData(
      tokenizer,
      dataHandler,
      remaining,
      prefetchRange: prefetchRange,
    );
    return atom;
  }

  Future<void> _readData(
    Tokenizer tokenizer,
    AtomDataHandler dataHandler,
    int remaining, {
    AtomPrefetchRange? prefetchRange,
  }) async {
    if (isContainer) {
      var payloadToRead = payloadLength;

      if (header.name == 'meta' && payloadToRead >= 4) {
        if (prefetchRange != null && payloadToRead >= 8) {
          await prefetchRange(tokenizer.position, tokenizer.position + 8);
        }
        final peekHeader = tokenizer.peekBytes(8);
        final probeName = String.fromCharCodes(peekHeader.sublist(4, 8));
        if (probeName != 'hdlr') {
          tokenizer.skip(4);
          payloadToRead -= 4;
        }
      }

      await readAtoms(
        tokenizer,
        dataHandler,
        payloadToRead,
        prefetchRange: prefetchRange,
      );
      return;
    }

    await dataHandler(this, payloadLength);
  }

  Future<void> readAtoms(
    Tokenizer tokenizer,
    AtomDataHandler dataHandler,
    int size, {
    AtomPrefetchRange? prefetchRange,
  }) async {
    var remaining = size;
    while (remaining > 0) {
      final child = await Mp4Atom.readAtom(
        tokenizer,
        dataHandler,
        this,
        remaining,
        prefetchRange: prefetchRange,
      );
      children.add(child);

      final consumed = child.header.length == 0
          ? remaining
          : child.header.length;
      if (consumed <= 0 || consumed > remaining) {
        break;
      }
      remaining -= consumed;
    }
  }

  static int _resolvePayloadLength({
    required AtomHeader header,
    required int remaining,
  }) {
    if (header.length == 0) {
      return remaining - header.headerLength;
    }

    final payload = header.length - header.headerLength;
    if (payload < 0) {
      throw Mp4ContentError('Invalid atom payload length for ${header.name}');
    }
    return payload;
  }
}
