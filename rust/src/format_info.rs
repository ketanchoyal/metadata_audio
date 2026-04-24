use symphonia::core::codecs::CodecParameters;
use symphonia::core::formats::{FormatReader, Track};
use symphonia::core::meta::{StandardTag, Tag};
use symphonia::core::units::{TimeBase, Timestamp};

use crate::api::*;
use crate::track_details::*;
use crate::utils::*;

pub(crate) fn extract_format(format: &mut dyn FormatReader) -> FfiFormat {
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
        chapters: vec![],
    }
}

pub(crate) fn normalize_container_short_name(short_name: &str) -> String {
    match short_name {
        "isomp4" => "mp4",
        "wave" => "wav",
        "mkv" => "matroska",
        value => value,
    }
    .to_string()
}

pub(crate) fn select_primary_audio_track<'a>(format: &'a dyn FormatReader) -> Option<&'a Track> {
    format
        .tracks()
        .iter()
        .find(|track| track.codec_params.as_ref().and_then(|params| params.audio()).is_some())
}

pub(crate) fn extract_track_format_details(
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

pub(crate) fn fallback_channel_count(audio: &symphonia::core::codecs::audio::AudioCodecParameters) -> Option<u32> {
    use symphonia::core::codecs::audio::well_known::CODEC_ID_AAC;

    if audio.codec == CODEC_ID_AAC {
        return parse_aac_channel_count(audio.extra_data.as_deref());
    }

    None
}

pub(crate) fn parse_aac_channel_count(extra_data: Option<&[u8]>) -> Option<u32> {
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

pub(crate) fn calculate_duration(
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

pub(crate) fn extract_bitrate(
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

pub(crate) fn extract_format_metadata_values(
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

pub(crate) fn apply_format_raw_values(
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

pub(crate) fn assign_replaygain_value(
    target: &mut Option<f64>,
    ratio_target: Option<&mut Option<f64>>,
    value: &str,
) {
    assign_option_from_value(target, value);
    if let Some(ratio_target) = ratio_target {
        assign_option_from_value(ratio_target, value);
    }
}

pub(crate) fn iter_revision_tags<'a>(revision: &'a symphonia::core::meta::MetadataRevision) -> Vec<&'a Tag> {
    let mut tags = Vec::new();
    tags.extend(revision.media.tags.iter());
    for per_track in &revision.per_track {
        tags.extend(per_track.metadata.tags.iter());
    }
    tags
}
