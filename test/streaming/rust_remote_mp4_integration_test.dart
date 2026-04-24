import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_audio/src/native/api.dart';
import 'package:metadata_audio/src/native/frb_generated.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<HttpServer> _startBytesServer(
  List<int> bytes, {
  String contentType = 'application/octet-stream',
  bool rejectHead = false,
  void Function(HttpRequest request)? onRequest,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final data = Uint8List.fromList(bytes);

  server.listen((request) async {
    onRequest?.call(request);
    if (rejectHead && request.method == 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    request.response.headers
      ..set('Accept-Ranges', 'bytes')
      ..set('Content-Type', contentType);

    final rangeHeader = request.headers.value('range');
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final spec = rangeHeader.substring('bytes='.length);
      final dash = spec.indexOf('-');
      final start = int.parse(spec.substring(0, dash));
      final endStr = spec.substring(dash + 1);
      final end = endStr.isEmpty ? data.length - 1 : int.parse(endStr);
      final sliceEnd = (end + 1).clamp(0, data.length);

      request.response.statusCode = 206;
      request.response.headers
        ..set('Content-Range', 'bytes $start-$end/${data.length}')
        ..contentLength = sliceEnd - start;
      if (request.method != 'HEAD') {
        request.response.add(data.sublist(start, sliceEnd));
      }
    } else {
      request.response.headers.contentLength = data.length;
      if (request.method != 'HEAD') {
        request.response.add(data);
      }
    }

    await request.response.close();
  });

  return server;
}

Future<HttpServer> _startSampleServer(
  String relPath, {
  String? contentType,
  bool rejectHead = false,
  void Function(HttpRequest request)? onRequest,
}) async {
  final bytes = await File(
    p.join(Directory.current.path, 'test', 'samples', relPath),
  ).readAsBytes();
  return _startBytesServer(
    bytes,
    contentType: contentType ?? 'audio/mp4',
    rejectHead: rejectHead,
    onRequest: onRequest,
  );
}

void main() {
  group('Rust remote MP4 parser integration', () {
    setUpAll(() async {
      await RustLib.init();
    });

    tearDownAll(() {
      RustLib.dispose();
    });

    test('parses chapter tracks from a local MP4 URL via Rust FFI', () async {
      final server = await _startSampleServer('mp4/sample.m4a');

      try {
        final chapters = await parseChaptersFromUrl(
          url: 'http://localhost:${server.port}/sample.m4a',
          timeoutMs: BigInt.from(5000),
        );

        expect(chapters, hasLength(3));
        expect(chapters[0].title, 'Chapter 1');
        expect(chapters[1].title, 'Chapter 2');
        expect(chapters[2].title, 'Chapter 3');
      } finally {
        await server.close(force: true);
      }
    });

    test('uses file size hints to skip HEAD in the Rust URL parser', () async {
      var headRequests = 0;
      final sampleFile = File(
        p.join(Directory.current.path, 'test', 'samples', 'mp4', 'sample.m4a'),
      );
      final sampleSize = await sampleFile.length();
      final server = await _startSampleServer(
        'mp4/sample.m4a',
        rejectHead: true,
        onRequest: (request) {
          if (request.method == 'HEAD') {
            headRequests++;
          }
        },
      );

      try {
        final chapters = await parseChaptersFromUrl(
          url: 'http://localhost:${server.port}/sample.m4a',
          timeoutMs: BigInt.from(5000),
          fileSizeHint: BigInt.from(sampleSize),
        );

        expect(chapters, hasLength(3));
        expect(headRequests, equals(0));
      } finally {
        await server.close(force: true);
      }
    });
  });
}
