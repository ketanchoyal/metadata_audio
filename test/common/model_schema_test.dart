import 'package:metadata_audio/src/model/types.dart';
import 'package:test/test.dart';

void main() {
  group('Tag', () {
    test('creates Tag with id and value', () {
      const tag = Tag(id: 'artist', value: 'The Beatles');
      expect(tag.id, 'artist');
      expect(tag.value, 'The Beatles');
    });

    test('Tag toString works', () {
      const tag = Tag(id: 'title', value: 'Hey Jude');
      expect(tag.toString(), contains('Tag'));
    });

    test('Tag with numeric value', () {
      const tag = Tag(id: 'year', value: 1969);
      expect(tag.value, 1969);
    });
  });

  group('ParserWarning', () {
    test('creates ParserWarning with message', () {
      const warning = ParserWarning(message: 'Invalid tag');
      expect(warning.message, 'Invalid tag');
    });

    test('ParserWarning toString works', () {
      const warning = ParserWarning(message: 'Test warning');
      expect(warning.toString(), contains('ParserWarning'));
    });
  });

  group('Picture', () {
    test('creates Picture with format and data', () {
      const picture = Picture(
        format: 'image/jpeg',
        data: [1, 2, 3, 4, 5],
        description: 'Cover art',
      );
      expect(picture.format, 'image/jpeg');
      expect(picture.data, [1, 2, 3, 4, 5]);
      expect(picture.description, 'Cover art');
    });

    test('Picture with optional fields', () {
      const picture = Picture(
        format: 'image/png',
        data: [],
        type: 'Front',
        name: 'cover.png',
      );
      expect(picture.type, 'Front');
      expect(picture.name, 'cover.png');
    });

    test('Picture toString includes format and size', () {
      const picture = Picture(format: 'image/jpeg', data: [1, 2, 3]);
      expect(picture.toString(), contains('image/jpeg'));
      expect(picture.toString(), contains('3'));
    });
  });

  group('Rating', () {
    test('creates Rating with source and rating', () {
      const rating = Rating(source: 'user@example.com', rating: 0.8);
      expect(rating.source, 'user@example.com');
      expect(rating.rating, 0.8);
    });

    test('Rating with null values', () {
      const rating = Rating();
      expect(rating.source, isNull);
      expect(rating.rating, isNull);
    });
  });

  group('Comment', () {
    test('creates Comment with text', () {
      const comment = Comment(
        descriptor: 'test',
        language: 'en',
        text: 'Great song',
      );
      expect(comment.text, 'Great song');
      expect(comment.language, 'en');
    });

    test('Comment with only text', () {
      const comment = Comment(text: 'Nice');
      expect(comment.text, 'Nice');
    });
  });

  group('LyricsText', () {
    test('creates LyricsText with text and timestamp', () {
      const lyrics = LyricsText(text: 'Hello world', timestamp: 1000);
      expect(lyrics.text, 'Hello world');
      expect(lyrics.timestamp, 1000);
    });

    test('LyricsText without timestamp', () {
      const lyrics = LyricsText(text: 'Verse 1');
      expect(lyrics.timestamp, isNull);
    });

    test('LyricsText toString truncates long text', () {
      const lyrics = LyricsText(
        text: 'This is a very long lyrics line that should be truncated',
      );
      expect(lyrics.toString(), contains('...'));
    });

    test('LyricsText toString for short text', () {
      const lyrics = LyricsText(text: 'Short');
      expect(lyrics.toString(), isNot(contains('...')));
    });
  });

  group('LyricsTag', () {
    test('creates LyricsTag with sync text', () {
      const lyrics = LyricsTag(
        contentType: 'lyrics',
        timeStampFormat: 'ms',
        syncText: [],
      );
      expect(lyrics.contentType, 'lyrics');
      expect(lyrics.timeStampFormat, 'ms');
    });

    test('LyricsTag with comment fields', () {
      const lyrics = LyricsTag(
        descriptor: 'test',
        language: 'en',
        text: 'Lyrics',
        contentType: 'lyrics',
        timeStampFormat: 'ms',
        syncText: [LyricsText(text: 'Line 1', timestamp: 0)],
      );
      expect(lyrics.text, 'Lyrics');
      expect(lyrics.syncText, hasLength(1));
    });
  });

  group('AudioTrack', () {
    test('creates AudioTrack with audio parameters', () {
      const track = AudioTrack(
        samplingFrequency: 44100,
        channels: 2,
        bitDepth: 16,
      );
      expect(track.samplingFrequency, 44100);
      expect(track.channels, 2);
      expect(track.bitDepth, 16);
    });

    test('AudioTrack with output frequency', () {
      const track = AudioTrack(
        samplingFrequency: 48000,
        outputSamplingFrequency: 44100,
      );
      expect(track.outputSamplingFrequency, 44100);
    });
  });

  group('VideoTrack', () {
    test('creates VideoTrack with video parameters', () {
      const track = VideoTrack(
        pixelWidth: 1920,
        pixelHeight: 1080,
        flagInterlaced: false,
      );
      expect(track.pixelWidth, 1920);
      expect(track.pixelHeight, 1080);
      expect(track.flagInterlaced, false);
    });

    test('VideoTrack with display dimensions', () {
      const track = VideoTrack(
        pixelWidth: 1920,
        pixelHeight: 1080,
        displayWidth: 1920,
        displayHeight: 1080,
      );
      expect(track.displayWidth, 1920);
    });
  });

  group('TrackInfo', () {
    test('creates TrackInfo with basic info', () {
      const track = TrackInfo(type: 'audio', codecName: 'aac', language: 'eng');
      expect(track.type, 'audio');
      expect(track.codecName, 'aac');
    });

    test('TrackInfo with audio track', () {
      const audioTrack = AudioTrack(channels: 2);
      const track = TrackInfo(type: 'audio', audio: audioTrack);
      expect(track.audio, isNotNull);
    });

    test('TrackInfo with video track', () {
      const videoTrack = VideoTrack(pixelWidth: 1920);
      const track = TrackInfo(type: 'video', video: videoTrack);
      expect(track.video, isNotNull);
    });
  });

  group('Url', () {
    test('creates Url with url and description', () {
      const url = Url(url: 'https://example.com', description: 'Chapter link');
      expect(url.url, 'https://example.com');
      expect(url.description, 'Chapter link');
    });
  });

  group('Chapter', () {
    test('creates Chapter with title and timestamps', () {
      const chapter = Chapter(title: 'Intro', start: 0, end: 30);
      expect(chapter.title, 'Intro');
      expect(chapter.start, 0);
      expect(chapter.end, 30);
    });

    test('Chapter with id and url', () {
      const url = Url(url: 'https://example.com', description: 'test');
      const chapter = Chapter(id: 'ch1', title: 'Verse', url: url, start: 30);
      expect(chapter.id, 'ch1');
      expect(chapter.url, isNotNull);
    });

    test('Chapter with sample offset', () {
      const chapter = Chapter(
        title: 'Bridge',
        start: 60,
        sampleOffset: 2646000,
        timeScale: 44100,
      );
      expect(chapter.sampleOffset, 2646000);
    });
  });

  group('Ratio', () {
    test('creates Ratio with ratio and dB', () {
      const ratio = Ratio(ratio: 0.9, dB: -0.915);
      expect(ratio.ratio, 0.9);
      expect(ratio.dB, -0.915);
    });
  });

  group('TrackNo', () {
    test('creates TrackNo with number and total', () {
      const trackNo = TrackNo(no: 5, of: 12);
      expect(trackNo.no, 5);
      expect(trackNo.of, 12);
    });

    test('TrackNo with only number', () {
      const trackNo = TrackNo(no: 3);
      expect(trackNo.no, 3);
      expect(trackNo.of, isNull);
    });

    test('TrackNo toString', () {
      const trackNo = TrackNo(no: 1, of: 10);
      expect(trackNo.toString(), contains('1/10'));
    });

    test('TrackNo toString without total', () {
      const trackNo = TrackNo(no: 5);
      expect(trackNo.toString(), contains('5'));
    });
  });

  group('Format', () {
    test('creates Format with basic info', () {
      const format = Format(
        container: 'flac',
        codec: 'FLAC',
        duration: 180.5,
        sampleRate: 44100,
      );
      expect(format.container, 'flac');
      expect(format.codec, 'FLAC');
      expect(format.duration, 180.5);
      expect(format.sampleRate, 44100);
    });

    test('Format with all parameters', () {
      const format = Format(
        container: 'mp3',
        tagTypes: ['ID3v2.4'],
        codec: 'MP3',
        bitrate: 320000,
        numberOfChannels: 2,
        lossless: false,
        hasAudio: true,
        hasVideo: false,
      );
      expect(format.lossless, false);
      expect(format.hasAudio, true);
      expect(format.tagTypes, ['ID3v2.4']);
    });

    test('Format with chapters', () {
      const chapter = Chapter(title: 'Ch1', start: 0);
      const format = Format(container: 'mp4', chapters: [chapter]);
      expect(format.chapters, hasLength(1));
    });

    test('Format with timestamps', () {
      final now = DateTime.now();
      final format = Format(
        container: 'wav',
        creationTime: now,
        modificationTime: now,
      );
      expect(format.creationTime, now);
    });

    test('Format with audio MD5', () {
      const format = Format(container: 'flac', audioMD5: [1, 2, 3, 4, 5]);
      expect(format.audioMD5, [1, 2, 3, 4, 5]);
    });
  });

  group('CommonTags', () {
    test('creates CommonTags with required fields', () {
      const track = TrackNo(no: 1, of: 10);
      const disk = TrackNo(no: 1, of: 1);
      const movementIndex = TrackNo();
      const tags = CommonTags(
        track: track,
        disk: disk,
        movementIndex: movementIndex,
        title: 'Test Song',
      );
      expect(tags.title, 'Test Song');
      expect(tags.track.no, 1);
    });

    test('CommonTags with artist and album', () {
      const track = TrackNo();
      const disk = TrackNo();
      const movementIndex = TrackNo();
      const tags = CommonTags(
        track: track,
        disk: disk,
        movementIndex: movementIndex,
        artist: 'Artist Name',
        album: 'Album Title',
        year: 2023,
      );
      expect(tags.artist, 'Artist Name');
      expect(tags.album, 'Album Title');
      expect(tags.year, 2023);
    });

    test('CommonTags with multiple artists', () {
      const track = TrackNo();
      const disk = TrackNo();
      const movementIndex = TrackNo();
      const tags = CommonTags(
        track: track,
        disk: disk,
        movementIndex: movementIndex,
        artists: ['Artist 1', 'Artist 2'],
      );
      expect(tags.artists, hasLength(2));
    });

    test('CommonTags with pictures', () {
      const picture = Picture(format: 'image/jpeg', data: [1, 2, 3]);
      const track = TrackNo();
      const disk = TrackNo();
      const movementIndex = TrackNo();
      const tags = CommonTags(
        track: track,
        disk: disk,
        movementIndex: movementIndex,
        picture: [picture],
      );
      expect(tags.picture, hasLength(1));
    });

    test('CommonTags with ratings', () {
      const rating = Rating(source: 'user', rating: 0.9);
      const track = TrackNo();
      const disk = TrackNo();
      const movementIndex = TrackNo();
      const tags = CommonTags(
        track: track,
        disk: disk,
        movementIndex: movementIndex,
        rating: [rating],
      );
      expect(tags.rating, hasLength(1));
    });

    test('CommonTags with MusicBrainz IDs', () {
      const track = TrackNo();
      const disk = TrackNo();
      const movementIndex = TrackNo();
      const tags = CommonTags(
        track: track,
        disk: disk,
        movementIndex: movementIndex,
        musicbrainz_trackid: 'mb-track-id',
        musicbrainz_albumid: 'mb-album-id',
      );
      expect(tags.musicbrainz_trackid, 'mb-track-id');
    });

    test('CommonTags with ReplayGain', () {
      const ratio = Ratio(ratio: 0.9, dB: -0.915);
      const track = TrackNo();
      const disk = TrackNo();
      const movementIndex = TrackNo();
      const tags = CommonTags(
        track: track,
        disk: disk,
        movementIndex: movementIndex,
        replaygain_track_gain_ratio: 0.9,
        replaygain_track_gain: ratio,
      );
      expect(tags.replaygain_track_gain_ratio, 0.9);
    });

    test('CommonTags toString', () {
      const track = TrackNo();
      const disk = TrackNo();
      const movementIndex = TrackNo();
      const tags = CommonTags(
        track: track,
        disk: disk,
        movementIndex: movementIndex,
        title: 'Test',
        artist: 'Artist',
      );
      expect(tags.toString(), contains('CommonTags'));
    });
  });

  group('QualityInformation', () {
    test('creates QualityInformation with no warnings', () {
      const quality = QualityInformation();
      expect(quality.warnings, isEmpty);
    });

    test('creates QualityInformation with warnings', () {
      const warning1 = ParserWarning(message: 'Warning 1');
      const warning2 = ParserWarning(message: 'Warning 2');
      const quality = QualityInformation(warnings: [warning1, warning2]);
      expect(quality.warnings, hasLength(2));
    });

    test('QualityInformation toString', () {
      const warning = ParserWarning(message: 'Test');
      const quality = QualityInformation(warnings: [warning]);
      expect(quality.toString(), contains('QualityInformation'));
    });
  });

  group('NativeTags', () {
    test('NativeTags is a Map type', () {
      const tag1 = Tag(id: 'test1', value: 'value1');
      const tag2 = Tag(id: 'test2', value: 'value2');
      final nativeTags = <String, List<Tag>>{
        'ID3v2': [tag1],
        'Vorbis': [tag2],
      };
      expect(nativeTags['ID3v2'], hasLength(1));
      expect(nativeTags['Vorbis'], hasLength(1));
    });
  });

  group('AudioMetadata', () {
    test('creates AudioMetadata with all components', () {
      const format = Format(container: 'mp3', codec: 'MP3');
      const nativeTags = <String, List<Tag>>{};
      const track = TrackNo();
      const disk = TrackNo();
      const movementIndex = TrackNo();
      const common = CommonTags(
        track: track,
        disk: disk,
        movementIndex: movementIndex,
        title: 'Song',
      );
      const quality = QualityInformation();

      const metadata = AudioMetadata(
        format: format,
        native: nativeTags,
        common: common,
        quality: quality,
      );

      expect(metadata.format.container, 'mp3');
      expect(metadata.common.title, 'Song');
      expect(metadata.quality.warnings, isEmpty);
    });

    test('AudioMetadata with native tags', () {
      const format = Format(container: 'flac');
      const tag = Tag(id: 'artist', value: 'The Beatles');
      final nativeTags = <String, List<Tag>>{
        'Vorbis': [tag],
      };
      const track = TrackNo();
      const disk = TrackNo();
      const movementIndex = TrackNo();
      const common = CommonTags(
        track: track,
        disk: disk,
        movementIndex: movementIndex,
      );
      const quality = QualityInformation();

      final metadata = AudioMetadata(
        format: format,
        native: nativeTags,
        common: common,
        quality: quality,
      );

      expect(metadata.native['Vorbis'], hasLength(1));
    });

    test('AudioMetadata with quality warnings', () {
      const format = Format(container: 'wav');
      const nativeTags = <String, List<Tag>>{};
      const track = TrackNo();
      const disk = TrackNo();
      const movementIndex = TrackNo();
      const common = CommonTags(
        track: track,
        disk: disk,
        movementIndex: movementIndex,
      );
      const warning = ParserWarning(message: 'Invalid tag');
      const quality = QualityInformation(warnings: [warning]);

      const metadata = AudioMetadata(
        format: format,
        native: nativeTags,
        common: common,
        quality: quality,
      );

      expect(metadata.quality.warnings, hasLength(1));
    });

    test('AudioMetadata toString', () {
      const format = Format(container: 'mp3');
      const nativeTags = <String, List<Tag>>{};
      const track = TrackNo();
      const disk = TrackNo();
      const movementIndex = TrackNo();
      const common = CommonTags(
        track: track,
        disk: disk,
        movementIndex: movementIndex,
        title: 'Test',
        artist: 'Artist',
      );
      const quality = QualityInformation();

      const metadata = AudioMetadata(
        format: format,
        native: nativeTags,
        common: common,
        quality: quality,
      );

      expect(metadata.toString(), contains('AudioMetadata'));
      expect(metadata.toString(), contains('mp3'));
    });
  });
}
