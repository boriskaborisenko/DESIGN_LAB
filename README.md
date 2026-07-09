# HLS Background Video

A static fullscreen hero page with an HLS-powered background video. The video starts from a random point on the timeline, so visitors do not download a huge source file upfront. The browser only requests the HLS segments needed around the current playback position.

The loop is intentionally smarter than a regular `<video loop>`: when playback reaches the end, the page prepares another video layer, seeks to a new random point, and crossfades to it instead of always returning to the beginning.

Original video source: <https://youtu.be/3L0Ph8KV0Tk?si=qeZ-Bw7PQbuX1Kdj>

## Why this approach

Large MP4 background videos are painful on mobile: heavy downloads, slower first paint, more bandwidth, more battery usage, and less reliable autoplay behavior. HLS solves this by splitting the video into small streamable segments.

This project uses:

- multi-bitrate HLS with a master playlist;
- 480p, 720p, and 1080p variants;
- native HLS on Safari, iPhone, and iPad;
- `hls.js` only for browsers that do not support HLS natively;
- muted inline autoplay for mobile compatibility;
- two video layers with CSS crossfade for smooth random jumps;
- a manual quality switcher: Auto, 480p, 720p, 1080p;
- a short quality recommendation based on screen/network hints;
- a poster image fallback when playback is blocked or unsupported.

## Project structure

```text
DESIGN_LAB/
  index.html                     # static site entrypoint
  README.md
  makeVideo.sh                   # HLS generation script
  RAW/
    .gitkeep                     # keep the folder, ignore raw video files
  videos/
    video_001/
      full/
        .gitkeep                 # keep the folder, ignore full/raw copies
      segments/
        master.m3u8              # multi-bitrate HLS master playlist
        index.m3u8               # compatibility alias to master.m3u8
        poster.jpg               # poster/fallback image
        480p/
          index.m3u8
          segment_00000.ts
          ...
        720p/
          index.m3u8
          segment_00000.ts
          ...
        1080p/
          index.m3u8
          segment_00000.ts
          ...
      video.json                 # generated metadata
```

## Current prepared video

The current HLS playlist is available at:

```text
videos/video_001/segments/master.m3u8
```

`videos/video_001/segments/index.m3u8` is kept as a compatibility alias.

The original source was about `675.7s`. The generated HLS output trims the first `10s` and the last `10s`, leaving about `655.7s` of playable video. Segments are about `10s` each.

Current variants:

```text
480p   lighter mobile / slower networks
720p   balanced desktop/mobile default
1080p  large screens / fast Wi-Fi
```

## Run locally

Do not test HLS through `file://`. Use a local HTTP server from the project root:

```bash
python3 -m http.server 8080
```

Then open:

```text
http://localhost:8080/index.html
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
./makeVideo.sh RAW/BIG_VIDEO.mp4 video_157 10 10 10 multi
```

Arguments:

```text
1. source           RAW/BIG_VIDEO.mp4
2. video_id         video_157
3. start_trim       seconds to trim from the beginning
4. end_trim         seconds to trim from the end
5. segment_seconds  HLS segment duration in seconds
6. mode             multi or single
```

In `multi` mode, the script creates:

```text
480p
720p
1080p
```

In `single` mode, it creates only a 720p stream.

## Use another generated video in HTML

Update these values in `index.html`:

```js
const QUALITY_SOURCES = {
  auto: { url: "videos/video_001/segments/master.m3u8" },
  "480p": { url: "videos/video_001/segments/480p/index.m3u8" },
  "720p": { url: "videos/video_001/segments/720p/index.m3u8" },
  "1080p": { url: "videos/video_001/segments/1080p/index.m3u8" }
};

const POSTER_URL = "videos/video_001/segments/poster.jpg";
const VIDEO_DURATION_SECONDS = 655.7;
```

For a newly generated video, use `trimmedDurationSeconds` from:

```text
videos/<video_id>/video.json
```

## Browser behavior

- Safari/iPhone/iPad use native HLS.
- Chrome/Firefox/Edge load `hls.js` dynamically.
- Auto quality uses the HLS master playlist and lets the player adapt.
- Manual quality buttons load a specific variant playlist.
- If HLS is unsupported or autoplay is blocked, the poster image remains visible.
- Random jumps and loop restarts use two video layers with a CSS crossfade.

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

Cloudflare Pages, Netlify, Vercel, and Render Static Sites usually serve static assets well, but if the video does not start, check MIME types, CORS headers, and whether the page is served over HTTP/HTTPS rather than `file://`.

## Git notes

The `RAW/` folder is kept in the repository for convenience, but its contents are ignored. `videos/*/full/*` is also ignored, so huge source videos are not committed accidentally.

Generated HLS segments under `videos/<video_id>/segments/` are intended to be deployed. The current `videos/video_001/full/.gitkeep` keeps the folder in the repo without adding the heavy original video.
