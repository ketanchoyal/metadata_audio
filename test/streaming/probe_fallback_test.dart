import 'dart:async';
import 'dart:io';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

List<int> _buildFrame({int bitrateIndex = 9}) {
  const sampleRate = 44100;
  const samplesPerFrame = 1152;
  final bitrateKbps = <int, int>{
    9: 128,
    10: 160,
  }[bitrateIndex]!;
  final bitrate = bitrateKbps * 1000;
  final frameLength = (samplesPerFrame / 8.0 * bitrate / sampleRate).floor();
  final header = <int>[0xFF, 0xFB, (bitrateIndex << 4), 0x40];
  final payload = List<int>.filled(frameLength - 4, 0);
  return <int>[...header, ...payload];
}

List<int> _encodeSynchsafeInt(int value) => [
  (value >> 21) & 0x7F,
  (value >> 14) & 0x7F,
  (value >> 7) & 0x7F,
  value & 0x7F,
];

List<int> _buildMalformedId3Tag(int payloadSize) {
  final payload = List<int>.filled(payloadSize, 0);
  payload.setRange(0, 10, const <int>[
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
  ]);
  return <int>[
    0x49,
    0x44,
    0x33,
    0x03,
    0x00,
    0x00,
    ..._encodeSynchsafeInt(payload.length),
    ...payload,
  ];
}

class _LocalServer {
  _LocalServer._(this._server, this._body) {
    _server.listen(_handle);
  }

  static Future<_LocalServer> start(List<int> body) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _LocalServer._(server, body);
  }

  final HttpServer _server;
  final List<int> _body;

  int get port => _server.port;
  String get url => 'http://localhost:$port/audio.mp3';

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    request.response.headers.contentType = ContentType('audio', 'mpeg');
    request.response.headers.set('Accept-Ranges', 'bytes');
    request.response.headers.contentLength = _body.length;

    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }

    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null && range.startsWith('bytes=')) {
      final parts = range.substring(6).split('-');
      final start = int.parse(parts.first);
      final end = parts.length > 1 && parts[1].isNotEmpty
          ? int.parse(parts[1])
          : _body.length - 1;
      final safeEnd = end.clamp(0, _body.length - 1);
      final safeStart = start.clamp(0, _body.length - 1);
      final rangeLength = safeEnd - safeStart + 1;
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $safeStart-$safeEnd/${_body.length}',
      );
      request.response.contentLength = rangeLength;
      request.response.add(_body.sublist(safeStart, safeEnd + 1));
      await request.response.close();
      return;
    }

    request.response.contentLength = _body.length;
    request.response.add(_body);
    await request.response.close();
  }
}

void main() {
  test('probe fallback retries full download for malformed ID3 MP3', () async {
    final frames = <int>[
      ..._buildFrame(),
      ..._buildFrame(bitrateIndex: 10),
      ..._buildFrame(),
    ];

    final body = <int>[
      ..._buildMalformedId3Tag(200 * 1024 - 10),
      ...List<int>.filled(200 * 1024, 0x55),
      ...frames,
      ...List<int>.filled(5 * 1024 * 1024, 0x00),
    ];

    final server = await _LocalServer.start(body);
    try {
      final metadata = await parseUrl(
        server.url,
        strategy: ParseStrategy.probe,
        options: const ParseOptions(duration: true),
      );

      expect(metadata.format.container, equals('MPEG'));
      expect(metadata.format.duration, isNotNull);
      expect(
        metadata.quality.warnings.map((warning) => warning.message),
        contains(contains('Invalid ID3v2.3 frame header ID')),
      );
    } finally {
      await server.close();
    }
  });
}
