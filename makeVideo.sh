#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./makeVideo.sh [source] [video_id] [start_trim] [end_trim] [segment_seconds] [width] [crf]

Examples:
  ./makeVideo.sh
  ./makeVideo.sh RAW/BIG_VIDEO.mp4 video_157
  ./makeVideo.sh RAW/BIG_VIDEO.mp4 video_157 10 10 10 1280 24

Defaults:
  source           first video file from RAW/
  video_id         video_<timestamp>
  start_trim       10 seconds
  end_trim         10 seconds
  segment_seconds  10 seconds
  width            1280 px
  crf              24

Output:
  videos/<video_id>/full/
  videos/<video_id>/segments/index.m3u8
  videos/<video_id>/segments/poster.jpg
  videos/<video_id>/segments/segment_00000.ts ...
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
WIDTH="${6:-1280}"
CRF="${7:-24}"

OUT_DIR="videos/${VIDEO_ID}"
FULL_DIR="${OUT_DIR}/full"
SEGMENTS_DIR="${OUT_DIR}/segments"
SOURCE_NAME="$(basename "$SOURCE")"
DURATION="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$SOURCE")"
TRIMMED_DURATION="$(awk -v duration="$DURATION" -v start="$START_TRIM" -v end="$END_TRIM" 'BEGIN { value = duration - start - end; if (value <= 0) exit 1; printf "%.3f", value }')"

mkdir -p "$FULL_DIR" "$SEGMENTS_DIR"
rm -f "${SEGMENTS_DIR}"/*

if [[ ! -f "${FULL_DIR}/${SOURCE_NAME}" ]]; then
  cp "$SOURCE" "${FULL_DIR}/${SOURCE_NAME}"
fi

ffmpeg -y \
  -ss "$START_TRIM" \
  -i "$SOURCE" \
  -t "$TRIMMED_DURATION" \
  -an \
  -vf "scale=${WIDTH}:-2" \
  -c:v libx264 \
  -preset medium \
  -crf "$CRF" \
  -profile:v main \
  -pix_fmt yuv420p \
  -force_key_frames "expr:gte(t,n_forced*${SEGMENT_SECONDS})" \
  -hls_time "$SEGMENT_SECONDS" \
  -hls_playlist_type vod \
  -hls_flags independent_segments \
  -hls_segment_filename "${SEGMENTS_DIR}/segment_%05d.ts" \
  "${SEGMENTS_DIR}/index.m3u8"

POSTER_TIME="$(awk -v start="$START_TRIM" 'BEGIN { printf "%.3f", start + 10 }')"

ffmpeg -y \
  -ss "$POSTER_TIME" \
  -i "$SOURCE" \
  -frames:v 1 \
  -update 1 \
  -vf "scale=${WIDTH}:-2" \
  "${SEGMENTS_DIR}/poster.jpg"

cat > "${OUT_DIR}/video.json" <<EOF
{
  "id": "${VIDEO_ID}",
  "source": "${FULL_DIR}/${SOURCE_NAME}",
  "playlist": "${SEGMENTS_DIR}/index.m3u8",
  "poster": "${SEGMENTS_DIR}/poster.jpg",
  "originalDurationSeconds": ${DURATION},
  "trimmedDurationSeconds": ${TRIMMED_DURATION},
  "startTrimSeconds": ${START_TRIM},
  "endTrimSeconds": ${END_TRIM},
  "segmentSeconds": ${SEGMENT_SECONDS},
  "width": ${WIDTH},
  "crf": ${CRF}
}
EOF

echo "Done."
echo "Playlist: ${SEGMENTS_DIR}/index.m3u8"
echo "Poster:   ${SEGMENTS_DIR}/poster.jpg"
echo "Config:   ${OUT_DIR}/video.json"
