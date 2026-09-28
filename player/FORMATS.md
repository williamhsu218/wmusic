# WMusic Supported Formats

Playback selects a decoder from **magic bytes**. Library scanning first filters
by supported file extensions, so renamed files may need a recognised extension
before they appear in the library.

Decoding uses two back-ends:

- **AVFoundation** — Apple's built-in audio stack. Zero extra dependencies.
- **FFmpeg** — this local build links Homebrew FFmpeg. Its current formula is
  GPL-3.0-or-later; see [local validation](../VALIDATION.md) before sharing a build.

---

## Lossless PCM

| Format | Extensions | Engine |
|---|---|---|
| WAV / RIFF PCM | `.wav` | AVFoundation |
| AIFF / AIFF-C | `.aiff` `.aif` | AVFoundation, FFmpeg fallback for exotic AIFF-C compression |
| AU / SND | `.au` `.snd` | FFmpeg |
| Wave64 | `.w64` | FFmpeg — removes the 4 GB WAV size limit |
| RF64 / Broadcast Wave | `.wav` `.bwf` | FFmpeg — detected by magic bytes, not extension |

## Lossless Compressed

| Format | Extensions | Engine |
|---|---|---|
| FLAC | `.flac` | AVFoundation (FFmpeg fallback for unusual streams) |
| ALAC | `.m4a` `.alac` `.mp4` | AVFoundation |
| Monkey's Audio | `.ape` | FFmpeg |
| WavPack | `.wv` | FFmpeg — lossless, hybrid-lossy, and DSD modes |

## Lossy

| Format | Extensions | Engine |
|---|---|---|
| MP3 (MPEG Layer 3) | `.mp3` | AVFoundation |
| MP2 (MPEG Layer 2) | `.mp2` | FFmpeg |
| MP1 (MPEG Layer 1) | `.mp1` | FFmpeg |
| AAC | `.aac` `.m4a` `.m4b` `.mp4` | AVFoundation |
| OGG Vorbis / Speex / Ogg FLAC | `.ogg` | FFmpeg — content type detected automatically |
| Opus | `.opus` `.ogg` | FFmpeg |
| WMA | `.wma` | FFmpeg (ASF container) |
| Musepack | `.mpc` | FFmpeg |
| AC-3 / Dolby Digital | `.ac3` | FFmpeg |
| DTS | `.dts` | FFmpeg |
| TTA (True Audio) | `.tta` | FFmpeg |

## DSD

DSD files are decoded by FFmpeg and converted to floating-point PCM for output.
This build does not provide native DSD or DoP passthrough.

| Format | Extensions | Engine |
|---|---|---|
| DSF | `.dsf` | FFmpeg — Sony DSD Stream File |
| DFF / DSDIFF | `.dff` | FFmpeg — Philips DSDIFF |

## Containers

| Format | Extensions | Engine |
|---|---|---|
| Matroska / MKV / WebM | `.mkv` `.mka` `.webm` | FFmpeg — audio tracks extracted automatically |
| MP4 / M4A | `.mp4` `.m4a` `.m4b` | AVFoundation |

---

## Output

All formats are decoded internally to **32-bit float PCM**. The available
hardware output format depends on the selected device and macOS audio path.

## What isn't supported

- **TAK** — the library scanner does not currently accept `.tak`, even though
  this machine's FFmpeg includes a TAK decoder
- **SACD ISO** — raw disc images; individual DSF/DFF tracks play fine
- **RealAudio** (`.ra`, `.rm`) — not accepted by the current library scanner
- **WMA Lossless / WMA Pro** — may fall back to FFmpeg probe; results vary
- **Encrypted files** — Apple DRM (FairPlay) and WMA DRM files will not play
