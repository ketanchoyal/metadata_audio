use symphonia::core::codecs::{CodecParameters, audio::AudioCodecId};
use symphonia::core::units::{TimeBase, Timestamp};

pub(crate) fn audio_codec_name(codec: AudioCodecId) -> String {
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

pub(crate) fn is_lossless_codec(codec: AudioCodecId) -> Option<bool> {
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

pub(crate) fn is_pcm_codec(codec: AudioCodecId) -> bool {
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

pub(crate) fn extract_track_details(
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
