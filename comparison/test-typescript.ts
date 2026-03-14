import * as mm from "music-metadata";
import * as path from "path";
import * as fs from "fs";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const samplesDir = path.join(__dirname, "..", "test", "samples");

interface TestResult {
  file: string;
  format: {
    container: string | undefined;
    codec: string | undefined;
    duration: number | undefined;
    sampleRate: number | undefined;
    numberOfChannels: number | undefined;
    bitrate: number | undefined;
    lossless?: boolean | undefined;
  };
  common: {
    title: string | undefined;
    artist: string | undefined;
    album: string | undefined;
    albumartist?: string | undefined;
    year: number | undefined;
    track: { no: number | null; of: number | null } | undefined;
    disk?: { no: number | null; of: number | null } | undefined;
    genre: string[] | undefined;
  };
  native: string[];
  error?: string;
}

async function parseFile(relativePath: string): Promise<TestResult> {
  const filePath = path.join(samplesDir, relativePath);

  if (!fs.existsSync(filePath)) {
    return {
      file: relativePath,
      format: {},
      common: {},
      native: [],
      error: "File not found",
    } as TestResult;
  }

  try {
    const metadata = await mm.parseFile(filePath);

    return {
      file: relativePath,
      format: {
        container: metadata.format.container,
        codec: metadata.format.codec,
        duration: metadata.format.duration,
        sampleRate: metadata.format.sampleRate,
        numberOfChannels: metadata.format.numberOfChannels,
        bitrate: metadata.format.bitrate,
        lossless: metadata.format.lossless,
      },
      common: {
        title: metadata.common.title,
        artist: metadata.common.artist,
        album: metadata.common.album,
        albumartist: metadata.common.albumartist,
        year: metadata.common.year,
        track: metadata.common.track,
        disk: metadata.common.disk,
        genre: metadata.common.genre,
      },
      native: Object.keys(metadata.native),
    };
  } catch (error) {
    return {
      file: relativePath,
      format: {},
      common: {},
      native: [],
      error: error instanceof Error ? error.message : String(error),
    } as TestResult;
  }
}

async function main() {
  const testFiles = [
    // MP3
    "mp3/id3v2.3.mp3",
    "mp3/id3v1.mp3",
    "mp3/no-tags.mp3",
    "mp3/issue-347.mp3",
    "mp3/adts-0-frame.mp3",
    // FLAC
    "flac/sample.flac",
    "flac/flac-multiple-album-artists-tags.flac",
    "flac/testcase.flac",
    // OGG
    "ogg/vorbis.ogg",
    "ogg/opus.ogg",
    // MP4
    "mp4/sample.m4a",
    "mp4/The Dark Forest.m4a",
    // WAV
    "wav/issue-819.wav",
    "wav/odd-list-type.wav",
    // AIFF
    "aiff/sample.aiff",
  ];

  const results: TestResult[] = [];

  for (const file of testFiles) {
    const result = await parseFile(file);
    results.push(result);
  }

  // Output only JSON, no console logs
  console.log(JSON.stringify(results, null, 2));
}

main().catch(console.error);
