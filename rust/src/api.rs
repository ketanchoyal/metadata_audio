#![allow(non_snake_case)]
#![allow(unexpected_cfgs)]

use std::fs::File;
use std::path::Path;

use symphonia::core::codecs::audio::AudioCodecId;
use symphonia::core::codecs::CodecParameters;
use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::{FormatOptions, FormatReader, Track};
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::{ChapterGroup, ChapterGroupItem, MetadataRevision, StandardTag, Tag};
use symphonia::core::units::{TimeBase, Timestamp};

#[derive(Debug)]
struct ExtractedMetadata {
    format_short_name: String,
    track_codec: Option<String>,
    duration_secs: Option<f64>,
    sample_rate: Option<u32>,
    channels: Option<u32>,
    bits_per_sample: Option<u32>,
    title: Option<String>,
    artist: Option<String>,
    album: Option<String>,
    native_tag_count: u32,
    has_pictures: bool,
    chapter_count: u32,
    warnings: Vec<String>,
}

#[flutter_rust_bridge::frb]
pub struct FfiBasicMetadata {
    pub container: Option<String>,
    pub codec: Option<String>,
    pub duration_secs: Option<f64>,
    pub sample_rate: Option<u32>,
    pub channels: Option<u32>,
    pub bits_per_sample: Option<u32>,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub native_tag_count: u32,
    pub has_pictures: bool,
    pub chapter_count: u32,
    pub warnings: Vec<String>,
}

#[derive(Clone, Debug, Default)]
#[flutter_rust_bridge::frb]
pub struct FfiTrackNo {
    pub no: Option<u32>,
    pub of: Option<u32>,
}

#[derive(Clone, Debug, Default)]
#[flutter_rust_bridge::frb]
pub struct FfiComment {
    pub descriptor: Option<String>,
    pub language: Option<String>,
    pub text: Option<String>,
}

#[derive(Clone, Debug, Default)]
#[flutter_rust_bridge::frb]
pub struct FfiRating {
    pub source: Option<String>,
    pub rating: Option<f64>,
}

#[derive(Clone, Debug, Default)]
#[flutter_rust_bridge::frb]
pub struct FfiPicture {
    pub format: Option<String>,
    pub data: Vec<u8>,
    pub description: Option<String>,
}

#[derive(Clone, Debug, Default)]
#[flutter_rust_bridge::frb]
pub struct FfiFormat {
    pub container: String,
    pub tag_types: Vec<String>,
    pub duration: Option<f64>,
    pub bitrate: Option<u32>,
    pub sample_rate: Option<u32>,
    pub bits_per_sample: Option<u32>,
    pub tool: Option<String>,
    pub codec: Option<String>,
    pub codec_profile: Option<String>,
    pub lossless: Option<bool>,
    pub number_of_channels: Option<u32>,
    pub number_of_samples: Option<u64>,
    pub has_audio: Option<bool>,
    pub has_video: Option<bool>,
    pub track_gain: Option<f64>,
    pub track_peak_level: Option<f64>,
    pub album_gain: Option<f64>,
}

#[derive(Clone, Debug, Default)]
#[flutter_rust_bridge::frb]
pub struct FfiLyricsTag {
    pub descriptor: Option<String>,
    pub language: Option<String>,
    pub text: Option<String>,
}

#[derive(Clone, Debug, Default)]
#[flutter_rust_bridge::frb]
pub struct FfiCommonTags {
    pub track: FfiTrackNo,
    pub disk: FfiTrackNo,
    pub year: Option<i32>,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub artists: Vec<String>,
    pub albumartist: Option<String>,
    pub albumartists: Vec<String>,
    pub album: Option<String>,
    pub date: Option<String>,
    pub originaldate: Option<String>,
    pub originalyear: Option<i32>,
    pub releasedate: Option<String>,
    pub comment: Vec<FfiComment>,
    pub genre: Vec<String>,
    pub picture: Vec<FfiPicture>,
    pub composer: Vec<String>,
    pub lyrics: Vec<FfiLyricsTag>,
    pub albumsort: Option<String>,
    pub titlesort: Option<String>,
    pub work: Option<String>,
    pub artistsort: Option<String>,
    pub albumartistsort: Option<String>,
    pub composersort: Option<String>,
    pub lyricist: Vec<String>,
    pub writer: Vec<String>,
    pub conductor: Vec<String>,
    pub remixer: Vec<String>,
    pub arranger: Vec<String>,
    pub engineer: Vec<String>,
    pub publisher: Vec<String>,
    pub producer: Vec<String>,
    pub djmixer: Vec<String>,
    pub mixer: Vec<String>,
    pub technician: Vec<String>,
    pub label: Vec<String>,
    pub grouping: Option<String>,
    pub subtitle: Vec<String>,
    pub description: Vec<String>,
    pub discsubtitle: Vec<String>,
    pub longDescription: Option<String>,
    pub totaltracks: Option<String>,
    pub totaldiscs: Option<String>,
    pub movementTotal: Option<i32>,
    pub compilation: Option<bool>,
    pub rating: Vec<FfiRating>,
    pub bpm: Option<i32>,
    pub mood: Option<String>,
    pub media: Option<String>,
    pub catalognumber: Vec<String>,
    pub tvShow: Option<String>,
    pub tvShowSort: Option<String>,
    pub tvEpisodeId: Option<String>,
    pub tvNetwork: Option<String>,
    pub tvSeason: Option<i32>,
    pub tvEpisode: Option<i32>,
    pub podcast: Option<bool>,
    pub podcasturl: Option<String>,
    pub releasestatus: Option<String>,
    pub releasecountry: Option<String>,
    pub script: Option<String>,
    pub language: Option<String>,
    pub copyright: Option<String>,
    pub license: Option<String>,
    pub encodedby: Option<String>,
    pub encodersettings: Option<String>,
    pub gapless: Option<String>,
    pub barcode: Option<String>,
    pub isrc: Option<String>,
    pub asin: Option<String>,
    pub website: Option<String>,
    pub notes: Option<String>,
    pub originalalbum: Option<String>,
    pub originalartist: Option<String>,
    pub releasetype: Vec<String>,
    pub keywords: Vec<String>,
    pub category: Vec<String>,
    pub musicbrainz_recordingid: Option<String>,
    pub musicbrainz_trackid: Option<String>,
    pub musicbrainz_albumid: Option<String>,
    pub musicbrainz_artistid: Option<String>,
    pub musicbrainz_albumartistid: Option<String>,
    pub musicbrainz_releasegroupid: Option<String>,
    pub musicbrainz_workid: Option<String>,
    pub musicbrainz_trmid: Option<String>,
    pub musicbrainz_discid: Option<String>,
    pub acoustid_id: Option<String>,
    pub acoustid_fingerprint: Option<String>,
    pub musicip_puid: Option<String>,
    pub musicip_fingerprint: Option<String>,
    pub discogs_artist_id: Option<String>,
    pub discogs_release_id: Option<String>,
    pub discogs_label_id: Option<String>,
    pub discogs_master_release_id: Option<String>,
    pub discogs_votes: Option<f64>,
    pub discogs_rating: Option<f64>,
    pub replaygain_track_gain: Option<f64>,
    pub replaygain_track_peak: Option<f64>,
    pub replaygain_album_gain: Option<f64>,
    pub replaygain_album_peak: Option<f64>,
    pub replaygain_track_gain_ratio: Option<f64>,
    pub replaygain_track_peak_ratio: Option<f64>,
    pub replaygain_album_minmax: Option<f64>,
    pub replaygain_track_minmax: Option<f64>,
    pub replaygain_undo: Option<f64>,
    pub performerInstrument: Option<String>,
    pub key: Option<String>,
    pub movement: Option<String>,
    pub stik: Option<String>,
    pub showMovement: Option<String>,
    pub playCounter: Option<String>,
    pub hdVideo: Option<String>,
    pub movementIndex: Option<i32>,
    pub podcastId: Option<String>,
}

#[derive(Debug)]
#[flutter_rust_bridge::frb]
pub struct FfiNativeTag {
    pub key: String,
    pub value: String,
    pub std_key: Option<String>,
}

#[flutter_rust_bridge::frb]
pub fn health_check() -> String {
    "symphonia-native-ok".to_string()
}

#[flutter_rust_bridge::frb]
pub fn poc_parse_file(path: String) -> Result<FfiBasicMetadata, String> {
    let file = File::open(&path).map_err(|err| format!("failed to open file '{path}': {err}"))?;

    let mut hint = Hint::new();
    if let Some(extension) = Path::new(&path).extension().and_then(|value| value.to_str()) {
        hint.with_extension(extension);
    }

    let stream = MediaSourceStream::new(Box::new(file), Default::default());
    let extracted = extract_basic_metadata(stream, hint)?;
    Ok(to_ffi_metadata(extracted))
}

#[flutter_rust_bridge::frb]
pub fn poc_parse_bytes(bytes: Vec<u8>, mime_hint: Option<String>) -> Result<FfiBasicMetadata, String> {
    let cursor = std::io::Cursor::new(bytes);
    let mut hint = Hint::new();

    if let Some(mime_hint) = mime_hint.as_deref() {
        hint.mime_type(mime_hint);
        if let Some(extension) = extension_from_mime(mime_hint) {
            hint.with_extension(extension);
        }
    }

    let stream = MediaSourceStream::new(Box::new(cursor), Default::default());
    let extracted = extract_basic_metadata(stream, hint)?;
    Ok(to_ffi_metadata(extracted))
}

#[flutter_rust_bridge::frb]
pub fn poc_get_common_tags(path: String) -> Result<FfiCommonTags, String> {
    let file = File::open(&path).map_err(|err| format!("failed to open file '{path}': {err}"))?;

    let mut hint = Hint::new();
    if let Some(extension) = Path::new(&path).extension().and_then(|value| value.to_str()) {
        hint.with_extension(extension);
    }

    let stream = MediaSourceStream::new(Box::new(file), Default::default());
    let mut format = symphonia::default::get_probe()
        .probe(&hint, stream, FormatOptions::default(), Default::default())
        .map_err(|err| format!("failed to probe media source stream: {err}"))?;

    Ok(extract_common_tags(&mut *format))
}

#[flutter_rust_bridge::frb]
pub fn poc_get_native_tags(path: String) -> Result<Vec<FfiNativeTag>, String> {
    let file = File::open(&path).map_err(|err| format!("failed to open file '{path}': {err}"))?;

    let mut hint = Hint::new();
    if let Some(extension) = Path::new(&path).extension().and_then(|value| value.to_str()) {
        hint.with_extension(extension);
    }

    let stream = MediaSourceStream::new(Box::new(file), Default::default());
    let mut format = symphonia::default::get_probe()
        .probe(&hint, stream, FormatOptions::default(), Default::default())
        .map_err(|err| format!("failed to probe media source stream: {err}"))?;

    Ok(collect_native_tags(&mut *format))
}

#[flutter_rust_bridge::frb]
pub fn poc_get_format(path: String) -> Result<FfiFormat, String> {
    let file = File::open(&path).map_err(|err| format!("failed to open file '{path}': {err}"))?;

    let mut hint = Hint::new();
    if let Some(extension) = Path::new(&path).extension().and_then(|value| value.to_str()) {
        hint.with_extension(extension);
    }

    let stream = MediaSourceStream::new(Box::new(file), Default::default());
    let mut format = symphonia::default::get_probe()
        .probe(&hint, stream, FormatOptions::default(), Default::default())
        .map_err(|err| format!("failed to probe media source stream: {err}"))?;

    Ok(extract_format(&mut *format))
}

fn extract_basic_metadata(stream: MediaSourceStream, hint: Hint) -> Result<ExtractedMetadata, String> {
    let mut format = symphonia::default::get_probe()
        .probe(&hint, stream, FormatOptions::default(), Default::default())
        .map_err(|err| format!("failed to probe media source stream: {err}"))?;

    let format_short_name = format.format_info().short_name.to_string();
    let track = format
        .tracks()
        .first()
        .ok_or_else(|| "no tracks discovered by Symphonia".to_string())?;

    let (track_codec, duration_secs, sample_rate, channels, bits_per_sample, track_warnings) =
        extract_track_details(
            track.codec_params.as_ref(),
            track.time_base,
            track.duration,
            track.num_frames,
        );

    let (title, artist, album, native_tag_count, has_pictures, metadata_warnings) =
        extract_metadata_details(&mut *format);

    let chapter_count = format.chapters().map(count_chapter_group_items).unwrap_or(0);

    let mut warnings = Vec::new();
    warnings.extend(track_warnings);
    warnings.extend(metadata_warnings);

    Ok(ExtractedMetadata {
        format_short_name,
        track_codec,
        duration_secs,
        sample_rate,
        channels,
        bits_per_sample,
        title,
        artist,
        album,
        native_tag_count,
        has_pictures,
        chapter_count,
        warnings,
    })
}

fn extract_track_details(
    codec_params: Option<&CodecParameters>,
    time_base: Option<TimeBase>,
    duration: Option<symphonia::core::units::Duration>,
    num_frames: Option<u64>,
) -> (Option<String>, Option<f64>, Option<u32>, Option<u32>, Option<u32>, Vec<String>) {
    let mut warnings = Vec::new();

    let Some(codec_params) = codec_params else {
        warnings.push("first track is missing codec parameters".to_string());
        return (None, None, None, None, None, warnings);
    };

    let Some(audio) = codec_params.audio() else {
        warnings.push("first track codec parameters are not audio".to_string());
        return (Some(format!("{codec_params:?}")), None, None, None, None, warnings);
    };

    let codec = Some(audio_codec_name(audio.codec));
    let sample_rate = audio.sample_rate;
    let channels = audio.channels.as_ref().map(|value| value.count() as u32);
    let bits_per_sample = audio.bits_per_sample.or(audio.bits_per_coded_sample);
    let duration_secs = match (time_base, duration, num_frames, sample_rate) {
        (Some(time_base), Some(duration), _, _) => duration
            .timestamp_from(Timestamp::ZERO)
            .and_then(|value| time_base.calc_time(value))
            .map(|value| value.as_secs_f64()),
        (_, None, Some(num_frames), Some(sample_rate)) if sample_rate > 0 => {
            Some(num_frames as f64 / sample_rate as f64)
        }
        (None, Some(_), _, _) => {
            warnings.push("track duration present without time base".to_string());
            None
        }
        _ => None,
    };

    if sample_rate.is_none() {
        warnings.push("sample rate unavailable on first track".to_string());
    }
    if channels.is_none() {
        warnings.push("channel count unavailable on first track".to_string());
    }
    if bits_per_sample.is_none() {
        warnings.push("bits per sample unavailable on first track".to_string());
    }
    if duration_secs.is_none() {
        warnings.push("duration unavailable from first track".to_string());
    }

    (codec, duration_secs, sample_rate, channels, bits_per_sample, warnings)
}

fn extract_metadata_details(
    format: &mut dyn FormatReader,
) -> (Option<String>, Option<String>, Option<String>, u32, bool, Vec<String>) {
    let mut metadata = format.metadata();
    let mut title = None;
    let mut artist = None;
    let mut album = None;
    let mut native_tag_count = 0u32;
    let mut has_pictures = false;
    let mut warnings = Vec::new();
    let mut revision_count = 0u32;

    while let Some(revision) = metadata.current() {
        revision_count += 1;
        let snapshot = summarize_revision(revision);
        native_tag_count = native_tag_count.saturating_add(snapshot.3);
        has_pictures |= snapshot.4;

        if title.is_none() {
            title = snapshot.0;
        }
        if artist.is_none() {
            artist = snapshot.1;
        }
        if album.is_none() {
            album = snapshot.2;
        }

        if metadata.pop().is_none() {
            break;
        }
    }

    if revision_count == 0 {
        warnings.push("metadata log contained no revisions".to_string());
    }
    if native_tag_count == 0 {
        warnings.push("no native tags found in metadata revisions".to_string());
    }

    (title, artist, album, native_tag_count, has_pictures, warnings)
}

fn extract_format(format: &mut dyn FormatReader) -> FfiFormat {
    let container = normalize_container_short_name(format.format_info().short_name);
    let has_audio = format.tracks().iter().any(|track| track.codec_params.as_ref().and_then(CodecParameters::audio).is_some());
    let has_video = format.tracks().iter().any(|track| track.codec_params.as_ref().and_then(|params| params.video()).is_some());

    let primary_track = select_primary_audio_track(format).or_else(|| format.tracks().first());

    let (
        codec,
        codec_profile,
        duration,
        bitrate,
        sample_rate,
        bits_per_sample,
        lossless,
        number_of_channels,
        number_of_samples,
    ) = primary_track
        .map(extract_track_format_details)
        .unwrap_or((None, None, None, None, None, None, None, None, None));

    let (tag_types, tool, track_gain, track_peak_level, album_gain) = extract_format_metadata_values(format);

    FfiFormat {
        container,
        tag_types,
        duration,
        bitrate,
        sample_rate,
        bits_per_sample,
        tool,
        codec,
        codec_profile,
        lossless,
        number_of_channels,
        number_of_samples,
        has_audio: Some(has_audio),
        has_video: Some(has_video),
        track_gain,
        track_peak_level,
        album_gain,
    }
}

fn normalize_container_short_name(short_name: &str) -> String {
    match short_name {
        "isomp4" => "mp4",
        "wave" => "wav",
        "mkv" => "matroska",
        value => value,
    }
    .to_string()
}

fn select_primary_audio_track<'a>(format: &'a dyn FormatReader) -> Option<&'a Track> {
    format
        .tracks()
        .iter()
        .find(|track| track.codec_params.as_ref().and_then(|params| params.audio()).is_some())
}

fn extract_track_format_details(
    track: &Track,
) -> (
    Option<String>,
    Option<String>,
    Option<f64>,
    Option<u32>,
    Option<u32>,
    Option<u32>,
    Option<bool>,
    Option<u32>,
    Option<u64>,
) {
    let Some(codec_params) = track.codec_params.as_ref() else {
        return (None, None, None, None, None, None, None, None, None);
    };

    let duration = calculate_duration(track.time_base, track.duration, track.num_frames, codec_params);
    let number_of_samples = track.num_frames;

    let Some(audio) = codec_params.audio() else {
        return (None, None, duration, None, None, None, None, None, number_of_samples);
    };

    let codec = Some(audio_codec_name(audio.codec));
    let codec_profile = audio.profile.map(|profile| profile.get().to_string());
    let sample_rate = audio.sample_rate;
    let bits_per_sample = audio.bits_per_sample.or(audio.bits_per_coded_sample);
    let number_of_channels = audio
        .channels
        .as_ref()
        .map(|channels| channels.count() as u32)
        .or_else(|| fallback_channel_count(audio));
    let lossless = is_lossless_codec(audio.codec);
    let bitrate = extract_bitrate(audio, duration, number_of_samples);

    (
        codec,
        codec_profile,
        duration,
        bitrate,
        sample_rate,
        bits_per_sample,
        lossless,
        number_of_channels,
        number_of_samples,
    )
}

fn fallback_channel_count(audio: &symphonia::core::codecs::audio::AudioCodecParameters) -> Option<u32> {
    use symphonia::core::codecs::audio::well_known::CODEC_ID_AAC;

    if audio.codec == CODEC_ID_AAC {
        return parse_aac_channel_count(audio.extra_data.as_deref());
    }

    None
}

fn parse_aac_channel_count(extra_data: Option<&[u8]>) -> Option<u32> {
    let data = extra_data?;
    if data.len() < 2 {
        return None;
    }

    let byte0 = data[0];
    let byte1 = data[1];
    let sample_rate_index = ((byte0 & 0x07) << 1) | (byte1 >> 7);
    let channel_config = (byte1 >> 3) & 0x0f;

    let offset = if sample_rate_index == 0x0f { 5 } else { 2 };
    if channel_config == 0 || data.len() < offset {
        return None;
    }

    Some(u32::from(channel_config))
}

fn calculate_duration(
    time_base: Option<TimeBase>,
    duration: Option<symphonia::core::units::Duration>,
    num_frames: Option<u64>,
    codec_params: &CodecParameters,
) -> Option<f64> {
    if let (Some(time_base), Some(duration)) = (time_base, duration) {
        if let Some(value) = duration
            .timestamp_from(Timestamp::ZERO)
            .and_then(|value| time_base.calc_time(value))
            .map(|value| value.as_secs_f64())
        {
            return Some(value);
        }
    }

    let sample_rate = codec_params.audio().and_then(|audio| audio.sample_rate)?;
    let num_frames = num_frames?;
    if sample_rate == 0 {
        return None;
    }

    Some(num_frames as f64 / sample_rate as f64)
}

fn extract_bitrate(
    audio: &symphonia::core::codecs::audio::AudioCodecParameters,
    duration: Option<f64>,
    number_of_samples: Option<u64>,
) -> Option<u32> {
    let bits_per_sample = audio.bits_per_coded_sample.or(audio.bits_per_sample);
    let channels = audio.channels.as_ref().map(|value| value.count() as u32);
    let sample_rate = audio.sample_rate;

    if is_pcm_codec(audio.codec) {
        if let (Some(bits_per_sample), Some(channels), Some(sample_rate)) = (bits_per_sample, channels, sample_rate) {
            return sample_rate.checked_mul(channels)?.checked_mul(bits_per_sample);
        }
    }

    if let (Some(duration), Some(number_of_samples), Some(bits_per_sample), Some(channels)) =
        (duration, number_of_samples, bits_per_sample, channels)
    {
        if duration > 0.0 {
            let bits = number_of_samples as f64 * f64::from(bits_per_sample) * f64::from(channels);
            let bitrate = (bits / duration).round();
            if bitrate.is_finite() && bitrate > 0.0 {
                return u32::try_from(bitrate as u64).ok();
            }
        }
    }

    None
}

fn is_lossless_codec(codec: AudioCodecId) -> Option<bool> {
    use symphonia::core::codecs::audio::well_known::*;

    match codec {
        CODEC_ID_FLAC
        | CODEC_ID_ALAC
        | CODEC_ID_PCM_S8
        | CODEC_ID_PCM_S16LE
        | CODEC_ID_PCM_S16BE
        | CODEC_ID_PCM_S24LE
        | CODEC_ID_PCM_S24BE
        | CODEC_ID_PCM_S32LE
        | CODEC_ID_PCM_S32BE
        | CODEC_ID_PCM_U8
        | CODEC_ID_PCM_U16LE
        | CODEC_ID_PCM_U16BE
        | CODEC_ID_PCM_U24LE
        | CODEC_ID_PCM_U24BE
        | CODEC_ID_PCM_U32LE
        | CODEC_ID_PCM_U32BE
        | CODEC_ID_PCM_F32LE
        | CODEC_ID_PCM_F32BE
        | CODEC_ID_PCM_F64LE
        | CODEC_ID_PCM_F64BE
        | CODEC_ID_PCM_ALAW
        | CODEC_ID_PCM_MULAW => Some(true),
        CODEC_ID_MP3 | CODEC_ID_AAC | CODEC_ID_VORBIS => Some(false),
        _ => None,
    }
}

fn is_pcm_codec(codec: AudioCodecId) -> bool {
    use symphonia::core::codecs::audio::well_known::*;

    matches!(
        codec,
        CODEC_ID_PCM_S8
            | CODEC_ID_PCM_S16LE
            | CODEC_ID_PCM_S16BE
            | CODEC_ID_PCM_S24LE
            | CODEC_ID_PCM_S24BE
            | CODEC_ID_PCM_S32LE
            | CODEC_ID_PCM_S32BE
            | CODEC_ID_PCM_U8
            | CODEC_ID_PCM_U16LE
            | CODEC_ID_PCM_U16BE
            | CODEC_ID_PCM_U24LE
            | CODEC_ID_PCM_U24BE
            | CODEC_ID_PCM_U32LE
            | CODEC_ID_PCM_U32BE
            | CODEC_ID_PCM_F32LE
            | CODEC_ID_PCM_F32BE
            | CODEC_ID_PCM_F64LE
            | CODEC_ID_PCM_F64BE
            | CODEC_ID_PCM_ALAW
            | CODEC_ID_PCM_MULAW
    )
}

fn extract_format_metadata_values(
    format: &mut dyn FormatReader,
) -> (Vec<String>, Option<String>, Option<f64>, Option<f64>, Option<f64>) {
    let mut metadata = format.metadata();
    let mut tag_types = Vec::new();
    let mut tool = None;
    let mut track_gain = None;
    let mut track_peak_level = None;
    let mut album_gain = None;

    while let Some(revision) = metadata.current() {
        push_unique(&mut tag_types, revision.info.short_name.to_string());

        for tag in iter_revision_tags(revision) {
            if tool.is_none() {
                match tag.std.as_ref() {
                    Some(StandardTag::Encoder(value)) | Some(StandardTag::EncoderSettings(value)) => {
                        tool = some_non_empty(value);
                    }
                    _ => {}
                }
            }

            apply_format_raw_values(&mut tool, &mut track_gain, &mut track_peak_level, &mut album_gain, tag);

            match tag.std.as_ref() {
                Some(StandardTag::ReplayGainTrackGain(value)) => assign_replaygain_value(&mut track_gain, None, value),
                Some(StandardTag::ReplayGainTrackPeak(value)) => assign_replaygain_value(&mut track_peak_level, None, value),
                Some(StandardTag::ReplayGainAlbumGain(value)) => assign_replaygain_value(&mut album_gain, None, value),
                _ => {}
            }
        }

        if metadata.pop().is_none() {
            break;
        }
    }

    (tag_types, tool, track_gain, track_peak_level, album_gain)
}

fn apply_format_raw_values(
    tool: &mut Option<String>,
    track_gain: &mut Option<f64>,
    track_peak_level: &mut Option<f64>,
    album_gain: &mut Option<f64>,
    tag: &Tag,
) {
    let key = tag.raw.key.trim();
    if key.is_empty() {
        return;
    }

    let value = tag.raw.value.to_string();
    match key.to_ascii_uppercase().as_str() {
        "ENCODER" | "ENCODEDBY" | "ENCODERSETTINGS" | "ENCENC" => {
            if tool.is_none() {
                *tool = some_non_empty(&value);
            }
        }
        "REPLAYGAIN_TRACK_GAIN" => assign_replaygain_value(track_gain, None, &value),
        "REPLAYGAIN_TRACK_PEAK" => assign_replaygain_value(track_peak_level, None, &value),
        "REPLAYGAIN_ALBUM_GAIN" => assign_replaygain_value(album_gain, None, &value),
        _ => {}
    }
}

fn summarize_revision(revision: &MetadataRevision) -> (Option<String>, Option<String>, Option<String>, u32, bool) {
    let mut title = None;
    let mut artist = None;
    let mut album = None;
    let mut tag_count = revision.media.tags.len() as u32;
    let mut has_pictures = !revision.media.visuals.is_empty();

    for tag in iter_revision_tags(revision) {
        if title.is_none() {
            title = extract_standard_tag_value(&tag.std, StandardTagKind::Title);
        }
        if artist.is_none() {
            artist = extract_standard_tag_value(&tag.std, StandardTagKind::Artist);
        }
        if album.is_none() {
            album = extract_standard_tag_value(&tag.std, StandardTagKind::Album);
        }
        tag_count = tag_count.saturating_add(1);
    }

    for per_track in &revision.per_track {
        has_pictures |= !per_track.metadata.visuals.is_empty();
    }

    (
        title,
        artist,
        album,
        tag_count.saturating_sub(1),
        has_pictures,
    )
}

fn extract_common_tags(format: &mut dyn FormatReader) -> FfiCommonTags {
    let mut metadata = format.metadata();
    let mut common = FfiCommonTags::default();

    while let Some(revision) = metadata.current() {
        common.artists.extend(collect_multi_value_tag(revision, StandardTagKind::Artist));
        common.albumartists.extend(collect_multi_value_tag(revision, StandardTagKind::AlbumArtist));
        common.genre.extend(collect_multi_value_tag(revision, StandardTagKind::Genre));
        common.composer.extend(collect_multi_value_tag(revision, StandardTagKind::Composer));
        common.lyricist.extend(collect_multi_value_tag(revision, StandardTagKind::Lyricist));
        common.writer.extend(collect_multi_value_tag(revision, StandardTagKind::Writer));
        common.conductor.extend(collect_multi_value_tag(revision, StandardTagKind::Conductor));
        common.remixer.extend(collect_multi_value_tag(revision, StandardTagKind::Remixer));
        common.arranger.extend(collect_multi_value_tag(revision, StandardTagKind::Arranger));
        common.engineer.extend(collect_multi_value_tag(revision, StandardTagKind::Engineer));
        common.publisher.extend(collect_multi_value_tag(revision, StandardTagKind::Publisher));
        common.producer.extend(collect_multi_value_tag(revision, StandardTagKind::Producer));
        common.djmixer.extend(collect_multi_value_tag(revision, StandardTagKind::DjMixer));
        common.mixer.extend(collect_multi_value_tag(revision, StandardTagKind::Mixer));
        common.label.extend(collect_multi_value_tag(revision, StandardTagKind::Label));
        common.subtitle.extend(collect_multi_value_tag(revision, StandardTagKind::Subtitle));
        common.description.extend(collect_multi_value_tag(revision, StandardTagKind::Description));
        common.discsubtitle.extend(collect_multi_value_tag(revision, StandardTagKind::DiscSubtitle));
        common.catalognumber.extend(collect_multi_value_tag(revision, StandardTagKind::CatalogNumber));
        common.category.extend(collect_multi_value_tag(revision, StandardTagKind::Category));
        common.keywords.extend(collect_multi_value_tag(revision, StandardTagKind::Keywords));
        common.releasetype.extend(collect_multi_value_tag(revision, StandardTagKind::ReleaseType));

        for tag in iter_revision_tags(revision) {
            apply_standard_tag(&mut common, tag);
            apply_raw_tag_fallbacks(&mut common, tag);
        }

        if metadata.pop().is_none() {
            break;
        }
    }

    dedup_strings(&mut common.artists);
    dedup_strings(&mut common.albumartists);
    dedup_strings(&mut common.genre);
    dedup_strings(&mut common.composer);
    dedup_strings(&mut common.lyricist);
    dedup_strings(&mut common.writer);
    dedup_strings(&mut common.conductor);
    dedup_strings(&mut common.remixer);
    dedup_strings(&mut common.arranger);
    dedup_strings(&mut common.engineer);
    dedup_strings(&mut common.publisher);
    dedup_strings(&mut common.producer);
    dedup_strings(&mut common.djmixer);
    dedup_strings(&mut common.mixer);
    dedup_strings(&mut common.technician);
    dedup_strings(&mut common.label);
    dedup_strings(&mut common.subtitle);
    dedup_strings(&mut common.description);
    dedup_strings(&mut common.discsubtitle);
    dedup_strings(&mut common.catalognumber);
    dedup_strings(&mut common.category);
    dedup_strings(&mut common.keywords);
    dedup_strings(&mut common.releasetype);

    common
}

fn track_no_from_tag(value: &str) -> FfiTrackNo {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return FfiTrackNo::default();
    }

    if let Some((no, of)) = trimmed.split_once('/') {
        return FfiTrackNo {
            no: parse_u32(no),
            of: parse_u32(of),
        };
    }

    FfiTrackNo {
        no: parse_u32(trimmed),
        of: None,
    }
}

fn parse_year_from_date(date: &str) -> Option<i32> {
    let bytes = date.as_bytes();
    for start in 0..bytes.len().saturating_sub(3) {
        let window = &bytes[start..start + 4];
        if window.iter().all(|ch| ch.is_ascii_digit()) {
            let year = std::str::from_utf8(window).ok()?.parse::<i32>().ok()?;
            if (1000..=2990).contains(&year) {
                return Some(year);
            }
        }
    }
    None
}

fn collect_multi_value_tag(revision: &MetadataRevision, kind: StandardTagKind) -> Vec<String> {
    let mut values = Vec::new();

    for tag in iter_revision_tags(revision) {
        if let Some(standard_tag) = tag.std.as_ref() {
            match (kind, standard_tag) {
                (StandardTagKind::Artist, StandardTag::Artist(value)) => push_multi_value(&mut values, value, false),
                (StandardTagKind::AlbumArtist, StandardTag::AlbumArtist(value)) => {
                    push_multi_value(&mut values, value, false)
                }
                (StandardTagKind::Genre, StandardTag::Genre(value)) => push_multi_value(&mut values, value, true),
                (StandardTagKind::Composer, StandardTag::Composer(value)) => {
                    push_multi_value(&mut values, value, false)
                }
                (StandardTagKind::Lyricist, StandardTag::Lyricist(value)) => {
                    push_multi_value(&mut values, value, false)
                }
                (StandardTagKind::Writer, StandardTag::Writer(value)) => push_multi_value(&mut values, value, false),
                (StandardTagKind::Conductor, StandardTag::Conductor(value)) => {
                    push_multi_value(&mut values, value, false)
                }
                (StandardTagKind::Remixer, StandardTag::Remixer(value)) => {
                    push_multi_value(&mut values, value, false)
                }
                (StandardTagKind::Arranger, StandardTag::Arranger(value)) => {
                    push_multi_value(&mut values, value, false)
                }
                (StandardTagKind::Engineer, StandardTag::Engineer(value)) => {
                    push_multi_value(&mut values, value, false)
                }
                (StandardTagKind::Publisher, StandardTag::Label(value)) => {
                    push_multi_value(&mut values, value, false)
                }
                (StandardTagKind::Producer, StandardTag::Producer(value))
                | (StandardTagKind::Producer, StandardTag::ExecutiveProducer(value)) => {
                    push_multi_value(&mut values, value, false)
                }
                (StandardTagKind::DjMixer, StandardTag::MixDj(value)) => {
                    push_multi_value(&mut values, value, false)
                }
                (StandardTagKind::Mixer, StandardTag::MixEngineer(value)) => {
                    push_multi_value(&mut values, value, false)
                }
                (StandardTagKind::Label, StandardTag::Label(value)) => push_multi_value(&mut values, value, false),
                (StandardTagKind::Subtitle, StandardTag::TrackSubtitle(value)) => {
                    push_multi_value(&mut values, value, false)
                }
                (StandardTagKind::Description, StandardTag::Description(value))
                | (StandardTagKind::Description, StandardTag::Summary(value))
                | (StandardTagKind::Description, StandardTag::Synopsis(value))
                | (StandardTagKind::Description, StandardTag::TvEpisodeTitle(value)) => {
                    push_multi_value(&mut values, value, false)
                }
                (StandardTagKind::DiscSubtitle, StandardTag::DiscSubtitle(value)) => {
                    push_multi_value(&mut values, value, false)
                }
                (StandardTagKind::CatalogNumber, StandardTag::IdentCatalogNumber(value)) => {
                    push_multi_value(&mut values, value, false)
                }
                (StandardTagKind::Category, StandardTag::PodcastCategory(value)) => {
                    push_multi_value(&mut values, value, true)
                }
                (StandardTagKind::Keywords, StandardTag::Keywords(value))
                | (StandardTagKind::Keywords, StandardTag::PodcastKeywords(value)) => {
                    push_multi_value(&mut values, value, true)
                }
                (StandardTagKind::ReleaseType, StandardTag::MusicBrainzReleaseType(value)) => {
                    push_multi_value(&mut values, value, true)
                }
                _ => {}
            }
        }
    }

    dedup_strings(&mut values);
    values
}

fn iter_revision_tags<'a>(revision: &'a MetadataRevision) -> Vec<&'a Tag> {
    let mut tags = Vec::new();
    tags.extend(revision.media.tags.iter());
    for per_track in &revision.per_track {
        tags.extend(per_track.metadata.tags.iter());
    }
    tags
}

fn apply_standard_tag(common: &mut FfiCommonTags, tag: &Tag) {
    let Some(std) = tag.std.as_ref() else {
        return;
    };

    match std {
        StandardTag::TrackTitle(value) => set_option_string(&mut common.title, value),
        StandardTag::Artist(value) => {
            set_option_string(&mut common.artist, value);
            push_multi_value(&mut common.artists, value, false);
        }
        StandardTag::Album(value) => set_option_string(&mut common.album, value),
        StandardTag::AlbumArtist(value) => {
            set_option_string(&mut common.albumartist, value);
            push_multi_value(&mut common.albumartists, value, false);
        }
        StandardTag::Genre(value) => push_multi_value(&mut common.genre, value, true),
        StandardTag::Composer(value) => push_multi_value(&mut common.composer, value, false),
        StandardTag::Lyricist(value) => push_multi_value(&mut common.lyricist, value, false),
        StandardTag::Writer(value) => push_multi_value(&mut common.writer, value, false),
        StandardTag::Conductor(value) => push_multi_value(&mut common.conductor, value, false),
        StandardTag::Remixer(value) => push_multi_value(&mut common.remixer, value, false),
        StandardTag::Arranger(value) => push_multi_value(&mut common.arranger, value, false),
        StandardTag::Engineer(value) => push_multi_value(&mut common.engineer, value, false),
        StandardTag::Producer(value) | StandardTag::ExecutiveProducer(value) => {
            push_multi_value(&mut common.producer, value, false);
        }
        StandardTag::Label(value) => push_multi_value(&mut common.label, value, false),
        StandardTag::Grouping(value) => set_option_string(&mut common.grouping, value),
        StandardTag::TrackSubtitle(value) => push_multi_value(&mut common.subtitle, value, false),
        StandardTag::Description(value)
        | StandardTag::Summary(value)
        | StandardTag::Synopsis(value) => push_multi_value(&mut common.description, value, false),
        StandardTag::Comment(_) => push_comment(&mut common.comment, comment_from_tag(tag)),
        StandardTag::Bpm(value) => set_option_i32(&mut common.bpm, *value as i64),
        StandardTag::Mood(value) => set_option_string(&mut common.mood, value),
        StandardTag::MediaFormat(value) => set_option_string(&mut common.media, value),
        StandardTag::IdentCatalogNumber(value) => push_multi_value(&mut common.catalognumber, value, false),
        StandardTag::TrackNumber(value) => {
            if common.track.no.is_none() {
                common.track.no = nonzero_u32_from_u64(*value);
            }
            let parsed = track_no_from_tag(&tag.raw.value.to_string());
            if common.track.of.is_none() {
                common.track.of = parsed.of;
                if common.totaltracks.is_none() {
                    common.totaltracks = parsed.of.map(|total| total.to_string());
                }
            }
        }
        StandardTag::DiscNumber(value) => {
            if common.disk.no.is_none() {
                common.disk.no = nonzero_u32_from_u64(*value);
            }
            let parsed = track_no_from_tag(&tag.raw.value.to_string());
            if common.disk.of.is_none() {
                common.disk.of = parsed.of;
                if common.totaldiscs.is_none() {
                    common.totaldiscs = parsed.of.map(|total| total.to_string());
                }
            }
        }
        StandardTag::TrackTotal(value) => {
            common.track.of = common.track.of.or_else(|| nonzero_u32_from_u64(*value));
            if common.totaltracks.is_none() {
                common.totaltracks = Some(value.to_string());
            }
        }
        StandardTag::DiscTotal(value) => {
            common.disk.of = common.disk.of.or_else(|| nonzero_u32_from_u64(*value));
            if common.totaldiscs.is_none() {
                common.totaldiscs = Some(value.to_string());
            }
        }
        StandardTag::ReleaseDate(value) => {
            set_option_string(&mut common.releasedate, value);
            set_option_string(&mut common.date, value);
            if common.year.is_none() {
                common.year = parse_year_from_date(value);
            }
        }
        StandardTag::ReleaseYear(value) => set_option_i32(&mut common.year, i64::from(*value)),
        StandardTag::RecordingDate(value) => {
            set_option_string(&mut common.date, value);
            if common.year.is_none() {
                common.year = parse_year_from_date(value);
            }
        }
        StandardTag::RecordingYear(value) => {
            set_option_i32(&mut common.year, i64::from(*value));
        }
        StandardTag::OriginalReleaseDate(value) | StandardTag::OriginalRecordingDate(value) => {
            set_option_string(&mut common.originaldate, value);
            if common.originalyear.is_none() {
                common.originalyear = parse_year_from_date(value);
            }
        }
        StandardTag::OriginalReleaseYear(value) | StandardTag::OriginalRecordingYear(value) => {
            set_option_i32(&mut common.originalyear, i64::from(*value));
        }
        StandardTag::Encoder(value) | StandardTag::EncoderSettings(value) => {
            set_option_string(&mut common.encodersettings, value);
        }
        StandardTag::EncodedBy(value) => set_option_string(&mut common.encodedby, value),
        StandardTag::Copyright(value) | StandardTag::ProductionCopyright(value) => {
            set_option_string(&mut common.copyright, value);
        }
        StandardTag::License(value) | StandardTag::TermsOfUse(value) => {
            set_option_string(&mut common.license, value);
        }
        StandardTag::IdentIsrc(value) => set_option_string(&mut common.isrc, value),
        StandardTag::IdentAsin(value) => set_option_string(&mut common.asin, value),
        StandardTag::IdentBarcode(value) => set_option_string(&mut common.barcode, value),
        StandardTag::Url(value)
        | StandardTag::UrlOfficial(value)
        | StandardTag::UrlArtist(value)
        | StandardTag::UrlLabel(value)
        | StandardTag::UrlSource(value)
        | StandardTag::UrlPurchase(value) => set_option_string(&mut common.website, value),
        StandardTag::CompilationFlag(value) => common.compilation = Some(*value),
        StandardTag::ReplayGainTrackGain(value) => {
            assign_replaygain_value(
                &mut common.replaygain_track_gain,
                Some(&mut common.replaygain_track_gain_ratio),
                value,
            );
        }
        StandardTag::ReplayGainTrackPeak(value) => {
            assign_replaygain_value(
                &mut common.replaygain_track_peak,
                Some(&mut common.replaygain_track_peak_ratio),
                value,
            );
        }
        StandardTag::ReplayGainAlbumGain(value) => {
            assign_replaygain_value(&mut common.replaygain_album_gain, None, value);
        }
        StandardTag::ReplayGainAlbumPeak(value) => {
            assign_replaygain_value(&mut common.replaygain_album_peak, None, value);
        }
        StandardTag::MusicBrainzRecordingId(value) => set_option_string(&mut common.musicbrainz_recordingid, value),
        StandardTag::MusicBrainzTrackId(value) => {
            set_option_string(&mut common.musicbrainz_trackid, value);
        }
        StandardTag::MusicBrainzReleaseTrackId(value) => {
            if common.musicbrainz_trackid.is_none() {
                set_option_string(&mut common.musicbrainz_trackid, value);
            }
        }
        StandardTag::MusicBrainzAlbumId(value) => set_option_string(&mut common.musicbrainz_albumid, value),
        StandardTag::MusicBrainzArtistId(value) => set_option_string(&mut common.musicbrainz_artistid, value),
        StandardTag::MusicBrainzAlbumArtistId(value) => {
            set_option_string(&mut common.musicbrainz_albumartistid, value);
        }
        StandardTag::MusicBrainzReleaseGroupId(value) => {
            set_option_string(&mut common.musicbrainz_releasegroupid, value);
        }
        StandardTag::MusicBrainzWorkId(value) => set_option_string(&mut common.musicbrainz_workid, value),
        StandardTag::MusicBrainzTrmId(value) => set_option_string(&mut common.musicbrainz_trmid, value),
        StandardTag::MusicBrainzDiscId(value) => set_option_string(&mut common.musicbrainz_discid, value),
        StandardTag::TvSeriesTitle(value) => set_option_string(&mut common.tvShow, value),
        StandardTag::SortTvSeriesTitle(value) => set_option_string(&mut common.tvShowSort, value),
        StandardTag::TvSeasonNumber(value) => set_option_i32(&mut common.tvSeason, *value as i64),
        StandardTag::TvEpisodeNumber(value) => set_option_i32(&mut common.tvEpisode, *value as i64),
        StandardTag::TvNetwork(value) => set_option_string(&mut common.tvNetwork, value),
        StandardTag::TvEpisodeTitle(value) => push_multi_value(&mut common.description, value, false),
        StandardTag::TvdbEpisodeId(value) => set_option_string(&mut common.tvEpisodeId, value),
        StandardTag::PodcastFlag(value) => common.podcast = Some(*value),
        StandardTag::UrlPodcast(value) => set_option_string(&mut common.podcasturl, value),
        StandardTag::PodcastCategory(value) => push_multi_value(&mut common.category, value, true),
        StandardTag::IdentPodcast(value) => set_option_string(&mut common.podcastId, value),
        StandardTag::MovementName(value) => set_option_string(&mut common.movement, value),
        StandardTag::MovementNumber(value) => set_option_i32(&mut common.movementIndex, *value as i64),
        StandardTag::MovementTotal(value) => set_option_i32(&mut common.movementTotal, *value as i64),
        StandardTag::SortTrackTitle(value) => set_option_string(&mut common.titlesort, value),
        StandardTag::SortArtist(value) => set_option_string(&mut common.artistsort, value),
        StandardTag::SortAlbum(value) => set_option_string(&mut common.albumsort, value),
        StandardTag::SortAlbumArtist(value) => set_option_string(&mut common.albumartistsort, value),
        StandardTag::SortComposer(value) => set_option_string(&mut common.composersort, value),
        StandardTag::Work(value) => set_option_string(&mut common.work, value),
        StandardTag::OriginalArtist(value) => set_option_string(&mut common.originalartist, value),
        StandardTag::OriginalAlbum(value) => set_option_string(&mut common.originalalbum, value),
        StandardTag::InitialKey(value) => set_option_string(&mut common.key, value),
        StandardTag::Keywords(value) | StandardTag::PodcastKeywords(value) => {
            push_multi_value(&mut common.keywords, value, true);
        }
        StandardTag::PlayCounter(value) => set_option_string(&mut common.playCounter, &value.to_string()),
        StandardTag::MixDj(value) => push_multi_value(&mut common.djmixer, value, false),
        StandardTag::MixEngineer(value) => push_multi_value(&mut common.mixer, value, false),
        StandardTag::MusicBrainzReleaseStatus(value) => set_option_string(&mut common.releasestatus, value),
        StandardTag::MusicBrainzReleaseType(value) => push_multi_value(&mut common.releasetype, value, true),
        StandardTag::ReleaseCountry(value) => set_option_string(&mut common.releasecountry, value),
        StandardTag::Script(value) => set_option_string(&mut common.script, value),
        StandardTag::Language(value) => set_option_string(&mut common.language, value),
        StandardTag::DiscSubtitle(value) => push_multi_value(&mut common.discsubtitle, value, false),
        StandardTag::PodcastDescription(value) => set_option_string(&mut common.longDescription, value),
        StandardTag::Performer(value) => set_option_string(&mut common.performerInstrument, value),
        StandardTag::Rating(value) => push_rating(&mut common.rating, rating_from_ppm(tag, *value)),
        StandardTag::Lyrics(_) => push_lyrics(&mut common.lyrics, lyrics_from_tag(tag)),
        StandardTag::PurchaseDate(value) => set_option_string(&mut common.releasedate, value),
        _ => {}
    }
}

fn apply_raw_tag_fallbacks(common: &mut FfiCommonTags, tag: &Tag) {
    let key = tag.raw.key.trim();
    if key.is_empty() {
        return;
    }

    let value = tag.raw.value.to_string();
    let key_upper = key.to_ascii_uppercase();

    match key_upper.as_str() {
        "TOTALTRACKS" => set_option_string(&mut common.totaltracks, &value),
        "TOTALDISCS" => set_option_string(&mut common.totaldiscs, &value),
        "DATE" => {
            set_option_string(&mut common.date, &value);
            if common.year.is_none() {
                common.year = parse_year_from_date(&value);
            }
        }
        "YEAR" => {
            set_option_i32_from_str(&mut common.year, &value);
        }
        "ORIGINALDATE" => {
            set_option_string(&mut common.originaldate, &value);
            if common.originalyear.is_none() {
                common.originalyear = parse_year_from_date(&value);
            }
        }
        "ORIGINALYEAR" => {
            set_option_i32_from_str(&mut common.originalyear, &value);
        }
        "DISCOGS_ARTIST_ID" => set_option_string(&mut common.discogs_artist_id, &value),
        "DISCOGS_RELEASE_ID" => set_option_string(&mut common.discogs_release_id, &value),
        "DISCOGS_LABEL_ID" => set_option_string(&mut common.discogs_label_id, &value),
        "DISCOGS_MASTER_RELEASE_ID" => set_option_string(&mut common.discogs_master_release_id, &value),
        "DISCOGS_VOTES" => assign_option_from_value(&mut common.discogs_votes, &value),
        "DISCOGS_RATING" => assign_option_from_value(&mut common.discogs_rating, &value),
        "REPLAYGAIN_TRACK_GAIN" => assign_replaygain_value(
            &mut common.replaygain_track_gain,
            Some(&mut common.replaygain_track_gain_ratio),
            &value,
        ),
        "REPLAYGAIN_TRACK_PEAK" => assign_replaygain_value(
            &mut common.replaygain_track_peak,
            Some(&mut common.replaygain_track_peak_ratio),
            &value,
        ),
        "REPLAYGAIN_ALBUM_GAIN" => assign_replaygain_value(&mut common.replaygain_album_gain, None, &value),
        "REPLAYGAIN_ALBUM_PEAK" => assign_replaygain_value(&mut common.replaygain_album_peak, None, &value),
        "REPLAYGAIN_TRACK_GAIN_RATIO" => assign_option_from_value(&mut common.replaygain_track_gain_ratio, &value),
        "REPLAYGAIN_TRACK_PEAK_RATIO" => assign_option_from_value(&mut common.replaygain_track_peak_ratio, &value),
        "REPLAYGAIN_ALBUM_MINMAX" => assign_option_from_value(&mut common.replaygain_album_minmax, &value),
        "REPLAYGAIN_TRACK_MINMAX" => assign_option_from_value(&mut common.replaygain_track_minmax, &value),
        "REPLAYGAIN_UNDO" | "MP3GAIN_UNDO" => assign_option_from_value(&mut common.replaygain_undo, &value),
        "MUSICIP_PUID" => set_option_string(&mut common.musicip_puid, &value),
        "MUSICIP_FINGERPRINT" => set_option_string(&mut common.musicip_fingerprint, &value),
        "ACOUSTID_ID" => set_option_string(&mut common.acoustid_id, &value),
        "ACOUSTID_FINGERPRINT" => set_option_string(&mut common.acoustid_fingerprint, &value),
        "GAPLESS" | "ITUNESGAPLESS" | "PGAP" => set_option_string(&mut common.gapless, &value),
        "TVSHOW" | "TVSHOWTITLE" => set_option_string(&mut common.tvShow, &value),
        "TVSHOWSORT" => set_option_string(&mut common.tvShowSort, &value),
        "TVEPISODEID" => set_option_string(&mut common.tvEpisodeId, &value),
        "TVSEASON" => set_option_i32_from_str(&mut common.tvSeason, &value),
        "TVEPISODE" => set_option_i32_from_str(&mut common.tvEpisode, &value),
        "PODCASTURL" => set_option_string(&mut common.podcasturl, &value),
        "LONGDESCRIPTION" => set_option_string(&mut common.longDescription, &value),
        "CONTENTGROUP" => push_multi_value(&mut common.description, &value, false),
        "NOTES" => set_option_string(&mut common.notes, &value),
        "ISRC" | "TSRC" => set_option_string(&mut common.isrc, &value),
        "BARCODE" => set_option_string(&mut common.barcode, &value),
        "ASIN" => set_option_string(&mut common.asin, &value),
        "ORIGINALALBUM" => set_option_string(&mut common.originalalbum, &value),
        "ORIGINALARTIST" => set_option_string(&mut common.originalartist, &value),
        "ENCODEDBY" => set_option_string(&mut common.encodedby, &value),
        "ENCODERSETTINGS" | "ENCODER_SETTINGS" => set_option_string(&mut common.encodersettings, &value),
        "LANGUAGE" => set_option_string(&mut common.language, &value),
        "SCRIPT" => set_option_string(&mut common.script, &value),
        "COPYRIGHT" => set_option_string(&mut common.copyright, &value),
        "LICENSE" => set_option_string(&mut common.license, &value),
        "KEY" | "INITIALKEY" => set_option_string(&mut common.key, &value),
        "MOVEMENT" => set_option_string(&mut common.movement, &value),
        "MOVEMENTTOTAL" => set_option_i32_from_str(&mut common.movementTotal, &value),
        "MOVEMENTINDEX" => set_option_i32_from_str(&mut common.movementIndex, &value),
        "PODCASTID" => set_option_string(&mut common.podcastId, &value),
        "WEBSITE" | "URL" => set_option_string(&mut common.website, &value),
        "HDVIDEO" | "HDVD" => set_option_string(&mut common.hdVideo, &value),
        "STIK" => set_option_string(&mut common.stik, &value),
        "SHOWMOVEMENT" | "SHWM" => set_option_string(&mut common.showMovement, &value),
        "TECHNICIAN" => push_multi_value(&mut common.technician, &value, false),
        "MUSICBRAINZ_RECORDINGID" => set_option_string(&mut common.musicbrainz_recordingid, &value),
        "MUSICBRAINZ_TRACKID" | "MUSICBRAINZ_RELEASETRACKID" => {
            set_option_string(&mut common.musicbrainz_trackid, &value)
        }
        "MUSICBRAINZ_ALBUMID" => set_option_string(&mut common.musicbrainz_albumid, &value),
        "MUSICBRAINZ_ARTISTID" => set_option_string(&mut common.musicbrainz_artistid, &value),
        "MUSICBRAINZ_ALBUMARTISTID" => set_option_string(&mut common.musicbrainz_albumartistid, &value),
        "MUSICBRAINZ_RELEASEGROUPID" => set_option_string(&mut common.musicbrainz_releasegroupid, &value),
        "MUSICBRAINZ_WORKID" => set_option_string(&mut common.musicbrainz_workid, &value),
        "MUSICBRAINZ_TRMID" => set_option_string(&mut common.musicbrainz_trmid, &value),
        "MUSICBRAINZ_DISCID" => set_option_string(&mut common.musicbrainz_discid, &value),
        "RELEASESTATUS" => set_option_string(&mut common.releasestatus, &value),
        "RELEASECOUNTRY" => set_option_string(&mut common.releasecountry, &value),
        _ => {}
    }

    if key == "iTunSMPB" {
        set_option_string(&mut common.gapless, &value);
    }

    if key_upper == "POPM" {
        push_rating(&mut common.rating, rating_from_popm(tag, &value));
    }
}

fn push_comment(comments: &mut Vec<FfiComment>, comment: FfiComment) {
    if comment.text.is_some() {
        comments.push(comment);
    }
}

fn push_rating(ratings: &mut Vec<FfiRating>, rating: FfiRating) {
    if rating.rating.is_some() {
        ratings.push(rating);
    }
}

fn push_lyrics(lyrics: &mut Vec<FfiLyricsTag>, tag: FfiLyricsTag) {
    if tag.text.is_some() {
        lyrics.push(tag);
    }
}

fn comment_from_tag(tag: &Tag) -> FfiComment {
    FfiComment {
        descriptor: raw_sub_field_value(tag, &["SHORT_DESCRIPTION", "DESCRIPTION"]),
        language: raw_sub_field_value(tag, &["LANGUAGE_BCP47", "LANGUAGE"]),
        text: some_non_empty(&tag.raw.value.to_string()),
    }
}

fn lyrics_from_tag(tag: &Tag) -> FfiLyricsTag {
    FfiLyricsTag {
        descriptor: raw_sub_field_value(tag, &["DESCRIPTION", "SHORT_DESCRIPTION"]),
        language: raw_sub_field_value(tag, &["LANGUAGE_BCP47", "LANGUAGE"]),
        text: some_non_empty(&tag.raw.value.to_string()),
    }
}

fn rating_from_ppm(tag: &Tag, rating_ppm: u32) -> FfiRating {
    FfiRating {
        source: raw_sub_field_value(tag, &["EMAIL", "OWNER"]),
        rating: Some(rating_ppm as f64 / 1_000_000.0),
    }
}

fn rating_from_popm(tag: &Tag, value: &str) -> FfiRating {
    let rating = parse_float(value).map(|parsed| if parsed > 1.0 { parsed / 255.0 } else { parsed });
    FfiRating {
        source: raw_sub_field_value(tag, &["EMAIL", "OWNER"]),
        rating,
    }
}

fn raw_sub_field_value(tag: &Tag, suffixes: &[&str]) -> Option<String> {
    tag.raw.sub_fields.as_ref().and_then(|sub_fields| {
        sub_fields.iter().find_map(|sub_field| {
            let field_upper = sub_field.field.to_ascii_uppercase();
            if suffixes.iter().any(|suffix| field_upper.ends_with(suffix)) {
                some_non_empty(&sub_field.value.to_string())
            } else {
                None
            }
        })
    })
}

fn set_option_string(target: &mut Option<String>, value: &str) {
    if target.is_none() {
        *target = some_non_empty(value);
    }
}

fn set_option_i32(target: &mut Option<i32>, value: i64) {
    if target.is_none() {
        *target = i32::try_from(value).ok();
    }
}

fn set_option_i32_from_str(target: &mut Option<i32>, value: &str) {
    if target.is_none() {
        *target = value.trim().parse::<i32>().ok();
    }
}

fn assign_option_from_value(target: &mut Option<f64>, value: &str) {
    if target.is_none() {
        *target = parse_float(value);
    }
}

fn assign_replaygain_value(
    target: &mut Option<f64>,
    ratio_target: Option<&mut Option<f64>>,
    value: &str,
) {
    assign_option_from_value(target, value);
    if let Some(ratio_target) = ratio_target {
        assign_option_from_value(ratio_target, value);
    }
}

fn push_multi_value(values: &mut Vec<String>, value: &str, split: bool) {
    let parts: Vec<String> = if split {
        split_multi_values(value)
    } else {
        some_non_empty(value).into_iter().collect()
    };

    for part in parts {
        push_unique(values, part);
    }
}

fn split_multi_values(value: &str) -> Vec<String> {
    let mut parts = Vec::new();
    for part in value.split(|ch| ch == ';' || ch == '/') {
        if let Some(cleaned) = some_non_empty(part) {
            parts.push(cleaned);
        }
    }

    if parts.is_empty() {
        some_non_empty(value).into_iter().collect()
    } else {
        parts
    }
}

fn push_unique(values: &mut Vec<String>, value: String) {
    if !values.iter().any(|existing| existing == &value) {
        values.push(value);
    }
}

fn dedup_strings(values: &mut Vec<String>) {
    let mut deduped = Vec::new();
    for value in values.drain(..) {
        push_unique(&mut deduped, value);
    }
    *values = deduped;
}

fn some_non_empty(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn parse_u32(value: &str) -> Option<u32> {
    value.trim().parse::<u32>().ok()
}

fn u32_from_u64(value: u64) -> Option<u32> {
    u32::try_from(value).ok()
}

fn nonzero_u32_from_u64(value: u64) -> Option<u32> {
    let value = u32_from_u64(value)?;
    if value == 0 { None } else { Some(value) }
}

fn parse_float(value: &str) -> Option<f64> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }

    if let Ok(parsed) = trimmed.parse::<f64>() {
        return Some(parsed);
    }

    let mut number = String::new();
    for (index, ch) in trimmed.chars().enumerate() {
        let allowed = ch.is_ascii_digit() || ch == '.' || (index == 0 && matches!(ch, '+' | '-'));
        if allowed {
            number.push(ch);
        } else if !number.is_empty() {
            break;
        }
    }

    number.parse::<f64>().ok()
}

fn collect_native_tags(format: &mut dyn FormatReader) -> Vec<FfiNativeTag> {
    let mut metadata = format.metadata();
    let mut native_tags = Vec::new();

    while let Some(revision) = metadata.current() {
        native_tags.extend(revision.media.tags.iter().map(tag_to_ffi_native_tag));
        for per_track in &revision.per_track {
            native_tags.extend(per_track.metadata.tags.iter().map(tag_to_ffi_native_tag));
        }

        if metadata.pop().is_none() {
            break;
        }
    }

    native_tags
}

fn tag_to_ffi_native_tag(tag: &Tag) -> FfiNativeTag {
    let std_key = tag.std.as_ref().map(standard_tag_key_name);
    let key = if tag.raw.key.is_empty() {
        tag.std.as_ref().and_then(mp4_atom_key_from_standard_tag).unwrap_or_default()
    } else {
        tag.raw.key.clone()
    };

    FfiNativeTag {
        key,
        value: tag.raw.value.to_string(),
        std_key,
    }
}

fn standard_tag_key_name(tag: &StandardTag) -> String {
    let debug = format!("{tag:?}");
    debug
        .split_once('(')
        .map(|(key, _)| key)
        .unwrap_or(debug.as_str())
        .to_string()
}

fn mp4_atom_key_from_standard_tag(tag: &StandardTag) -> Option<String> {
    let atom = match tag {
        StandardTag::AlbumArtist(_) => "aART",
        StandardTag::Album(_) => "©alb",
        StandardTag::Arranger(_) => "©arg",
        StandardTag::Artist(_) => "©ART",
        StandardTag::Author(_) => "©aut",
        StandardTag::Bpm(_) => "tmpo",
        StandardTag::Comment(_) => "©cmt",
        StandardTag::CompilationFlag(_) => "cpil",
        StandardTag::Composer(_) => "©wrt",
        StandardTag::Conductor(_) => "©con",
        StandardTag::Copyright(_) => "cprt",
        StandardTag::Description(_) => "desc",
        StandardTag::DiscNumber(_) | StandardTag::DiscTotal(_) => "disk",
        StandardTag::EncodedBy(_) => "©enc",
        StandardTag::Encoder(_) | StandardTag::EncoderSettings(_) => "©too",
        StandardTag::Genre(_) => "©gen",
        StandardTag::Grouping(_) => "©grp",
        StandardTag::IdentIsrc(_) => "©isr",
        StandardTag::IdentPodcast(_) => "egid",
        StandardTag::Label(_) => "©lab",
        StandardTag::Lyrics(_) => "©lyr",
        StandardTag::MovementName(_) => "©mvn",
        StandardTag::MovementNumber(_) => "©mvi",
        StandardTag::MovementTotal(_) => "©mvc",
        StandardTag::OriginalArtist(_) => "©ope",
        StandardTag::PodcastCategory(_) => "catg",
        StandardTag::PodcastFlag(_) => "pcst",
        StandardTag::PodcastKeywords(_) => "keyw",
        StandardTag::Producer(_) => "©prd",
        StandardTag::ProductionCopyright(_) => "©phg",
        StandardTag::PurchaseDate(_) => "purd",
        StandardTag::ReleaseDate(_) => "©day",
        StandardTag::SortAlbum(_) => "soal",
        StandardTag::SortAlbumArtist(_) => "soaa",
        StandardTag::SortArtist(_) => "soar",
        StandardTag::SortComposer(_) => "soco",
        StandardTag::SortTrackTitle(_) => "sonm",
        StandardTag::TrackNumber(_) | StandardTag::TrackTotal(_) => "trkn",
        StandardTag::TrackTitle(_) => "©nam",
        StandardTag::TvEpisodeNumber(_) => "tves",
        StandardTag::TvEpisodeTitle(_) => "tven",
        StandardTag::TvNetwork(_) => "tvnn",
        StandardTag::TvSeasonNumber(_) => "tvsn",
        StandardTag::TvSeriesTitle(_) => "tvsh",
        StandardTag::UrlPodcast(_) => "purl",
        StandardTag::Work(_) => "©wrk",
        StandardTag::Writer(_) => "©wrt",
        _ => return None,
    };

    Some(atom.to_string())
}

fn extract_standard_tag_value(tag: &Option<StandardTag>, kind: StandardTagKind) -> Option<String> {
    match (tag, kind) {
        (Some(StandardTag::TrackTitle(value)), StandardTagKind::Title) => Some(value.to_string()),
        (Some(StandardTag::Artist(value)), StandardTagKind::Artist) => Some(value.to_string()),
        (Some(StandardTag::Album(value)), StandardTagKind::Album) => Some(value.to_string()),
        _ => None,
    }
}

fn count_chapter_group_items(group: &ChapterGroup) -> u32 {
    group
        .items
        .iter()
        .map(|item| match item {
            ChapterGroupItem::Chapter(_) => 1,
            ChapterGroupItem::Group(group) => count_chapter_group_items(group),
        })
        .sum()
}

fn to_ffi_metadata(value: ExtractedMetadata) -> FfiBasicMetadata {
    FfiBasicMetadata {
        container: Some(value.format_short_name),
        codec: value.track_codec,
        duration_secs: value.duration_secs,
        sample_rate: value.sample_rate,
        channels: value.channels,
        bits_per_sample: value.bits_per_sample,
        title: value.title,
        artist: value.artist,
        album: value.album,
        native_tag_count: value.native_tag_count,
        has_pictures: value.has_pictures,
        chapter_count: value.chapter_count,
        warnings: value.warnings,
    }
}

fn audio_codec_name(codec: symphonia::core::codecs::audio::AudioCodecId) -> String {
    use symphonia::core::codecs::audio::well_known::{
        CODEC_ID_AAC, CODEC_ID_ALAC, CODEC_ID_FLAC, CODEC_ID_MP3, CODEC_ID_VORBIS,
    };

    if codec == CODEC_ID_MP3 {
        "MPEG 1 Layer 3".to_string()
    } else if codec == CODEC_ID_FLAC {
        "FLAC".to_string()
    } else if codec == CODEC_ID_VORBIS {
        "Vorbis I".to_string()
    } else if codec == CODEC_ID_AAC {
        "MPEG-4/AAC".to_string()
    } else if codec == CODEC_ID_ALAC {
        "ALAC".to_string()
    } else {
        codec.to_string()
    }
}

fn extension_from_mime(mime: &str) -> Option<&'static str> {
    match mime {
        "audio/mpeg" | "audio/mp3" | "audio/mpeg3" => Some("mp3"),
        "audio/flac" | "audio/x-flac" => Some("flac"),
        "audio/mp4" | "audio/x-m4a" | "audio/m4a" => Some("m4a"),
        "audio/ogg" | "audio/vorbis" | "audio/ogg; codecs=vorbis" => Some("ogg"),
        _ => None,
    }
}

#[derive(Copy, Clone)]
enum StandardTagKind {
    Title,
    Artist,
    Album,
    AlbumArtist,
    Genre,
    Composer,
    Lyricist,
    Writer,
    Conductor,
    Remixer,
    Arranger,
    Engineer,
    Publisher,
    Producer,
    DjMixer,
    Mixer,
    Label,
    Subtitle,
    Description,
    DiscSubtitle,
    CatalogNumber,
    Category,
    Keywords,
    ReleaseType,
}
