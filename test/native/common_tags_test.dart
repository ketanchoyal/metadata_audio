import 'dart:io';

import 'package:metadata_audio/src/native/api.dart';
import 'package:metadata_audio/src/native/frb_generated.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Symphonia common tags mapping', () {
    setUpAll(RustLib.init);
    tearDownAll(RustLib.dispose);

    String sample(String relativePath) =>
        p.join(Directory.current.path, 'test', 'samples', relativePath);

    test('extracts rich MP3 common tags', () async {
      final tags = await pocGetCommonTags(path: sample('mp3/id3v2.3.mp3'));

      expect(tags.title, 'Home');
      expect(tags.artist, 'Explosions In The Sky/Another/');
      expect(tags.album, startsWith('Friday Night Lights [Original'));
      expect(tags.albumartist, 'Soundtrack');
      expect(tags.track.no, 5);
      expect(tags.track.of, isNull);
      expect(tags.disk.no, 1);
      expect(tags.disk.of, 1);
      expect(tags.genre, contains('Soundtrack'));
      expect(tags.composer, contains('Explosions in the Sky'));
      expect(tags.date, isNull);
      expect(tags.year, 2004);
      expect(tags.performerInstrument, isNull);
      expect(tags.replaygainTrackPeak, isNull);
      expect(tags.replaygainAlbumGain, isNull);
    });

    test('extracts rich FLAC common tags', () async {
      final tags = await pocGetCommonTags(path: sample('flac/sample.flac'));

      expect(tags.title, 'Mi Korasón');
      expect(tags.artist, 'Yasmin Levy');
      expect(tags.album, 'Sentir');
      expect(tags.albumartist, 'Yasmin Levy');
      expect(tags.track.no, 1);
      expect(tags.track.of, 12);
      expect(tags.disk.no, 1);
      expect(tags.disk.of, 1);
      expect(tags.totaltracks, '12');
      expect(tags.totaldiscs, '1');
      expect(tags.catalognumber, contains('450010'));
      expect(tags.releasestatus, 'official');
      expect(tags.releasecountry, 'XE');
      expect(tags.script, 'Latn');
      expect(tags.asin, 'B002HNA9MW');
      expect(tags.barcode, '794881933624');
      expect(tags.genre, contains('Folk, World, & Country'));
      expect(tags.producer, contains('Javier Limón'));
      expect(tags.label, contains('Adama Music'));
      expect(tags.year, 2009);
      expect(tags.originalyear, 2009);
      expect(tags.originaldate, '2009-10-05');
      expect(tags.releasetype, contains('album'));
      expect(tags.musicbrainzAlbumid, '5738c4b9-f5e3-4671-ab7a-b279fe917c6f');
      expect(tags.musicbrainzTrackid, '16fbdc8a-bf8f-369e-9452-3f43b14d27a1');
      expect(tags.musicbrainzReleasegroupid, '46ae6c2b-530d-4b19-b31d-88cd34b2900a');
      expect(tags.musicbrainzAlbumartistid, '856e486f-21f3-4203-a5d2-e30993988b38');
      expect(tags.discogsReleaseId, '3520814');
      expect(tags.discogsLabelId, '76596');
      expect(tags.discogsMasterReleaseId, '461710');
      expect(tags.discogsArtistId, '467650');
      expect(tags.discogsVotes, 3);
      expect(tags.discogsRating, closeTo(4.33, 0.001));
      expect(tags.replaygainTrackGain, closeTo(-4.97, 0.001));
      expect(tags.replaygainAlbumGain, closeTo(-5.98, 0.001));
      expect(tags.replaygainTrackPeak, closeTo(0.982910, 0.0001));
      expect(tags.replaygainAlbumPeak, closeTo(0.982941, 0.0001));
      expect(tags.acoustidId, '5ed423d9-5048-4b13-99f2-b15f5368c8eb');
    });

    test('extracts common tags from MP4 fixture', () async {
      final tags = await pocGetCommonTags(path: sample('mp4/sample.m4a'));

      expect(tags.title, 'Testcase');
      expect(tags.artist, 'Testcase');
      expect(tags.album, 'Testcase');
      expect(tags.track.no, 1);
      expect(tags.genre, contains('Testcase'));
      expect(tags.date, '2023');
      expect(tags.year, 2023);
      expect(tags.comment.single.text, 'Testcase');
      expect(tags.encodersettings, 'Lavf60.3.100');
      expect(tags.track.of, isNull);
      expect(tags.albumartist, isNull);
      expect(tags.releasedate, '2023');
      expect(tags.track.of, isNull);
    });

    test('extracts common tags from OGG fixture', () async {
      final tags = await pocGetCommonTags(path: sample('ogg/vorbis.ogg'));

      expect(tags.title, 'In Bloom');
      expect(tags.artist, 'Nirvana');
      expect(tags.album, 'Nevermind');
      expect(tags.albumartist, 'Nirvana');
      expect(tags.track.no, 2);
      expect(tags.track.of, 12);
      expect(tags.disk.no, 1);
      expect(tags.disk.of, 1);
      expect(tags.genre, containsAll(['Grunge', 'Alternative']));
      expect(tags.comment.single.text, "Nirvana's Greatest Album");
      expect(tags.label, contains('Geffen Records'));
      expect(tags.engineer, contains('James Johnson'));
      expect(tags.mixer, contains('Andy Wallace'));
      expect(tags.producer, contains('Butch Vig'));
      expect(tags.releasecountry, 'US');
      expect(tags.releasestatus, 'official');
      expect(tags.releasetype, contains('album'));
      expect(tags.script, 'Latn');
      expect(tags.asin, 'B000003TA4');
      expect(tags.barcode, '0720642442524');
      expect(tags.catalognumber, contains('GED24425'));
      expect(tags.media, 'CD');
      expect(tags.originaldate, '1991-09-23');
      expect(tags.originalyear, 1991);
      expect(tags.musicbrainzAlbumid, '8e061dc4-790e-4587-ba53-011e7852f88d');
      expect(tags.musicbrainzTrackid, '5e55fa04-d664-3653-a1c9-0b660b08f846');
      expect(tags.musicbrainzArtistid, '5b11f4ce-a62d-471e-81fc-a69a8278c7da');
      expect(tags.musicbrainzAlbumartistid, '5b11f4ce-a62d-471e-81fc-a69a8278c7da');
      expect(tags.musicbrainzReleasegroupid, '1b022e01-4da6-387b-8658-8678046e4cef');
    });
  });
}
