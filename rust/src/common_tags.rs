use symphonia::core::formats::FormatReader;
use symphonia::core::meta::{MetadataRevision, StandardTag, Tag};

use crate::api::*;
use crate::utils::*;

pub(crate) fn extract_common_tags(format: &mut dyn FormatReader) -> FfiCommonTags {
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

pub(crate) fn track_no_from_tag(value: &str) -> FfiTrackNo {
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

pub(crate) fn parse_year_from_date(date: &str) -> Option<i32> {
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

pub(crate) fn collect_multi_value_tag(revision: &MetadataRevision, kind: StandardTagKind) -> Vec<String> {
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

pub(crate) fn iter_revision_tags<'a>(revision: &'a MetadataRevision) -> Vec<&'a Tag> {
    let mut tags = Vec::new();
    tags.extend(revision.media.tags.iter());
    for per_track in &revision.per_track {
        tags.extend(per_track.metadata.tags.iter());
    }
    tags
}

pub(crate) fn apply_standard_tag(common: &mut FfiCommonTags, tag: &Tag) {
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

pub(crate) fn apply_raw_tag_fallbacks(common: &mut FfiCommonTags, tag: &Tag) {
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

pub(crate) fn push_comment(comments: &mut Vec<FfiComment>, comment: FfiComment) {
    if comment.text.is_some() {
        comments.push(comment);
    }
}

pub(crate) fn push_rating(ratings: &mut Vec<FfiRating>, rating: FfiRating) {
    if rating.rating.is_some() {
        ratings.push(rating);
    }
}

pub(crate) fn push_lyrics(lyrics: &mut Vec<FfiLyricsTag>, tag: FfiLyricsTag) {
    if tag.text.is_some() {
        lyrics.push(tag);
    }
}

pub(crate) fn comment_from_tag(tag: &Tag) -> FfiComment {
    FfiComment {
        descriptor: raw_sub_field_value(tag, &["SHORT_DESCRIPTION", "DESCRIPTION"]),
        language: raw_sub_field_value(tag, &["LANGUAGE_BCP47", "LANGUAGE"]),
        text: some_non_empty(&tag.raw.value.to_string()),
    }
}

pub(crate) fn lyrics_from_tag(tag: &Tag) -> FfiLyricsTag {
    FfiLyricsTag {
        descriptor: raw_sub_field_value(tag, &["DESCRIPTION", "SHORT_DESCRIPTION"]),
        language: raw_sub_field_value(tag, &["LANGUAGE_BCP47", "LANGUAGE"]),
        text: some_non_empty(&tag.raw.value.to_string()),
    }
}

pub(crate) fn rating_from_ppm(tag: &Tag, rating_ppm: u32) -> FfiRating {
    FfiRating {
        source: raw_sub_field_value(tag, &["EMAIL", "OWNER"]),
        rating: Some(rating_ppm as f64 / 1_000_000.0),
    }
}

pub(crate) fn rating_from_popm(tag: &Tag, value: &str) -> FfiRating {
    let rating = parse_float(value).map(|parsed| if parsed > 1.0 { parsed / 255.0 } else { parsed });
    FfiRating {
        source: raw_sub_field_value(tag, &["EMAIL", "OWNER"]),
        rating,
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

pub(crate) fn push_multi_value(values: &mut Vec<String>, value: &str, split: bool) {
    let parts: Vec<String> = if split {
        split_multi_values(value)
    } else {
        some_non_empty(value).into_iter().collect()
    };

    for part in parts {
        push_unique(values, part);
    }
}

pub(crate) fn split_multi_values(value: &str) -> Vec<String> {
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
