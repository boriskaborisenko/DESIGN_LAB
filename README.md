# HLS Background Video

A static fullscreen hero page with an HLS-powered background video. The video starts from a random point on the timeline, so visitors do not download a huge source file upfront. The browser only requests the HLS segments needed around the current playback position.

The loop is intentionally smarter than a regular `<video loop>`: when playback reaches the end, the page jumps to a new random point instead of always returning to the beginning. This keeps the background feeling more alive and less repetitive.

## Why this approach

Large MP4 background videos are painful on mobile: heavy downloads, slower first paint, more bandwidth, more battery usage, and less reliable autoplay behavior. HLS solves this by splitting the video into small streamable segments.

This project uses:

- native HLS on Safari, iPhone, and iPad;
- `hls.js` only for browsers that do not support HLS natively;
- muted inline autoplay for mobile compatibility;
- a poster image fallback when playback is blocked or unsupported;
- random timeline starts for a less repetitive background.

## Project structure

```text
DESIGN_LAB/
  RAW/
    .gitkeep                     # keep the folder, ignore raw video files
  videos/
    video_001/
      full/                      # optional source copy created by the script
      segments/
        index.m3u8               # HLS playlist
        poster.jpg               # poster/fallback image
        segment_00000.ts
        segment_00001.ts
        ...
      video.json                 # generated metadata
  makeVideo.sh                   # HLS generation script
  video_bg.html                  # demo page
```

## Current prepared video

The current HLS playlist is available at:

```text
videos/video_001/segments/index.m3u8
```

The original source was about `675.7s`. The generated HLS output trims the first `10s` and the last `10s`, leaving about `655.7s` of playable video. Segments are about `10s` each.

## Run locally

Do not test HLS through `file://`. Use a local HTTP server from the project root:

```bash
python3 -m http.server 8080
```

Then open:

```text
http://localhost:8080/video_bg.html
```

## Generate HLS from a new raw video

1. Put your source video into:

```text
RAW/
```

2. Run:

```bash
./makeVideo.sh
```

By default, the script uses the first video file found in `RAW/` and creates an output folder like:

```text
videos/video_<timestamp>/
```

## Generate with explicit parameters

```bash
./makeVideo.sh RAW/BIG_VIDEO.mp4 video_157 10 10 10 1280 24
```

Arguments:

```text
1. source           RAW/BIG_VIDEO.mp4
2. video_id         video_157
3. start_trim       seconds to trim from the beginning
4. end_trim         seconds to trim from the end
5. segment_seconds  HLS segment duration in seconds
6. width            output video width in px
7. crf              libx264 quality/compression value
```

Recommended `crf` values:

```text
22  very good quality, larger files
24  balanced quality and size
26  smaller files, lower quality
28  lighter mobile/background output
```

## Use another generated video in HTML

Update these constants in `video_bg.html`:

```js
const HLS_URL = "videos/video_001/segments/index.m3u8";
const POSTER_URL = "videos/video_001/segments/poster.jpg";
const VIDEO_DURATION_SECONDS = 655.7;
```

For a newly generated video, use `trimmedDurationSeconds` from:

```text
videos/<video_id>/video.json
```

Example:

```js
const HLS_URL = "videos/video_157/segments/index.m3u8";
const POSTER_URL = "videos/video_157/segments/poster.jpg";
const VIDEO_DURATION_SECONDS = 655.7;
```

## Browser behavior

- Safari/iPhone/iPad use native HLS.
- Chrome/Firefox/Edge load `hls.js` dynamically.
- If HLS is unsupported or autoplay is blocked, the poster image remains visible.
- When playback reaches the end, the script seeks to a new random point instead of looping back to the beginning.

For reliable mobile autoplay, the video must be muted and inline:

```html
autoplay muted playsinline
```

The current HTML already sets these attributes and also applies extra iOS-friendly properties such as `webkit-playsinline`, disabled remote playback, and disabled picture-in-picture.

## Server MIME types

For production, make sure your static server/CDN serves HLS files with correct MIME types:

```text
.m3u8 -> application/vnd.apple.mpegurl
.ts   -> video/mp2t
.jpg  -> image/jpeg
```

Cloudflare Pages, Netlify, and Vercel usually serve static assets correctly. If the video does not start, check MIME types, CORS headers, and whether the page is served over HTTP/HTTPS rather than `file://`.

## Git notes

The `RAW/` folder is kept in the repository for convenience, but its contents are ignored. This prevents huge source videos from being committed accidentally.
