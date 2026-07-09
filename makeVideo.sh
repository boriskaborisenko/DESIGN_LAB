#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./makeVideo.sh [source] [video_id] [start_trim] [end_trim] [segment_seconds] [mode]

Examples:
  ./makeVideo.sh
  ./makeVideo.sh RAW/BIG_VIDEO.mp4 video_157
  ./makeVideo.sh RAW/BIG_VIDEO.mp4 video_157 10 10 10 multi
  ./makeVideo.sh RAW/BIG_VIDEO.mp4 video_157 10 10 10 single

Defaults:
  source           first video file from RAW/
  video_id         video_<timestamp>
  start_trim       10 seconds
  end_trim         10 seconds
  segment_seconds  10 seconds
  mode             multi

Output:
  videos/<video_id>/full/                     # kept empty by default; raw copies are gitignored
  videos/<video_id>/segments/master.m3u8      # multi-bitrate entrypoint
  videos/<video_id>/segments/index.m3u8       # compatibility alias to master.m3u8
  videos/<video_id>/segments/poster.jpg
  videos/<video_id>/segments/480p/index.m3u8
  videos/<video_id>/segments/720p/index.m3u8
  videos/<video_id>/segments/1080p/index.m3u8
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Error: ffmpeg is not installed."
  exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "Error: ffprobe is not installed."
  exit 1
fi

SOURCE="${1:-}"

if [[ -z "$SOURCE" ]]; then
  SOURCE="$(find RAW -maxdepth 1 -type f \( -iname '*.mp4' -o -iname '*.mov' -o -iname '*.m4v' -o -iname '*.webm' \) | sort | head -n 1)"
fi

if [[ -z "$SOURCE" || ! -f "$SOURCE" ]]; then
  echo "Error: source video not found. Put a video into RAW/ or pass path explicitly."
  usage
  exit 1
fi

VIDEO_ID="${2:-video_$(date +%s)}"
START_TRIM="${3:-10}"
END_TRIM="${4:-10}"
SEGMENT_SECONDS="${5:-10}"
MODE="${6:-multi}"

OUT_DIR="videos/${VIDEO_ID}"
FULL_DIR="${OUT_DIR}/full"
SEGMENTS_DIR="${OUT_DIR}/segments"
SOURCE_NAME="$(basename "$SOURCE")"
DURATION="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$SOURCE")"
TRIMMED_DURATION="$(awk -v duration="$DURATION" -v start="$START_TRIM" -v end="$END_TRIM" 'BEGIN { value = duration - start - end; if (value <= 0) exit 1; printf "%.3f", value }')"

mkdir -p "$FULL_DIR" "$SEGMENTS_DIR"
rm -rf "${SEGMENTS_DIR:?}"/*

touch "${FULL_DIR}/.gitkeep"

make_variant() {
  local name="$1"
  local width="$2"
  local crf="$3"
  local bandwidth="$4"
  local resolution="$5"
  local variant_dir="${SEGMENTS_DIR}/${name}"

  mkdir -p "$variant_dir"

  echo "Generating ${name} (${width}px, crf ${crf})..."

  ffmpeg -y \
    -ss "$START_TRIM" \
    -i "$SOURCE" \
    -t "$TRIMMED_DURATION" \
    -an \
    -vf "scale=${width}:-2" \
    -c:v libx264 \
    -preset medium \
    -crf "$crf" \
    -maxrate "$bandwidth" \
    -bufsize "$(awk -v bw="$bandwidth" 'BEGIN { gsub(/k/, "", bw); printf "%dk", bw * 2 }')" \
    -profile:v main \
    -pix_fmt yuv420p \
    -force_key_frames "expr:gte(t,n_forced*${SEGMENT_SECONDS})" \
    -hls_time "$SEGMENT_SECONDS" \
    -hls_playlist_type vod \
    -hls_flags independent_segments \
    -hls_segment_filename "${variant_dir}/segment_%05d.ts" \
    "${variant_dir}/index.m3u8"

  echo "${name}|${bandwidth}|${resolution}" >> "${SEGMENTS_DIR}/.variants"
}

if [[ "$MODE" == "single" ]]; then
  make_variant "720p" "1280" "24" "2800k" "1280x720"

  cat > "${SEGMENTS_DIR}/master.m3u8" <<EOF
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720,CODECS="avc1.4d401f"
720p/index.m3u8
EOF

  cp "${SEGMENTS_DIR}/master.m3u8" "${SEGMENTS_DIR}/index.m3u8"
else
  : > "${SEGMENTS_DIR}/.variants"

  make_variant "480p" "854" "27" "1100k" "854x480"
  make_variant "720p" "1280" "24" "2800k" "1280x720"
  make_variant "1080p" "1920" "23" "5500k" "1920x1080"

  cat > "${SEGMENTS_DIR}/master.m3u8" <<EOF
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-STREAM-INF:BANDWIDTH=1100000,RESOLUTION=854x480,CODECS="avc1.4d401f"
480p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720,CODECS="avc1.4d401f"
720p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5500000,RESOLUTION=1920x1080,CODECS="avc1.4d4028"
1080p/index.m3u8
EOF

  cp "${SEGMENTS_DIR}/master.m3u8" "${SEGMENTS_DIR}/index.m3u8"
fi

POSTER_TIME="$(awk -v start="$START_TRIM" 'BEGIN { printf "%.3f", start + 10 }')"

ffmpeg -y \
  -ss "$POSTER_TIME" \
  -i "$SOURCE" \
  -frames:v 1 \
  -update 1 \
  -vf "scale=1280:-2" \
  "${SEGMENTS_DIR}/poster.jpg"

cat > "${OUT_DIR}/video.json" <<EOF
{
  "id": "${VIDEO_ID}",
  "source": "${SOURCE}",
  "playlist": "${SEGMENTS_DIR}/master.m3u8",
  "compatPlaylist": "${SEGMENTS_DIR}/index.m3u8",
  "poster": "${SEGMENTS_DIR}/poster.jpg",
  "originalDurationSeconds": ${DURATION},
  "trimmedDurationSeconds": ${TRIMMED_DURATION},
  "startTrimSeconds": ${START_TRIM},
  "endTrimSeconds": ${END_TRIM},
  "segmentSeconds": ${SEGMENT_SECONDS},
  "mode": "${MODE}",
  "variants": [
    { "name": "480p", "width": 854, "bandwidth": 1100000, "crf": 27 },
    { "name": "720p", "width": 1280, "bandwidth": 2800000, "crf": 24 },
    { "name": "1080p", "width": 1920, "bandwidth": 5500000, "crf": 23 }
  ]
}
EOF

rm -f "${SEGMENTS_DIR}/.variants"

echo "Done."
echo "Playlist: ${SEGMENTS_DIR}/master.m3u8"
echo "Alias:    ${SEGMENTS_DIR}/index.m3u8"
echo "Poster:   ${SEGMENTS_DIR}/poster.jpg"
echo "Config:   ${OUT_DIR}/video.json"
