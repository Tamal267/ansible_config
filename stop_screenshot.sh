#!/bin/bash

set -eu

# Stop screenshot daemon
pkill -f "screenshot_daemon.sh" || true

SCREENSHOT_DIR="/tmp/screenshots"
OUTPUT_VIDEO="/tmp/contest_session.mp4"

if [ -d "$SCREENSHOT_DIR" ] && compgen -G "$SCREENSHOT_DIR/*.png" > /dev/null; then
    echo "Creating MP4 video from captured screenshots..."

    if command -v ffmpeg &> /dev/null; then
        ffmpeg -framerate 5 -pattern_type glob -i "$SCREENSHOT_DIR/*.png" \
               -c:v libx264 -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -pix_fmt yuv420p "$OUTPUT_VIDEO" -y >/dev/null 2>&1 || true
        if [ -f "$OUTPUT_VIDEO" ]; then
            chmod 666 "$OUTPUT_VIDEO"
            echo "Video created successfully at $OUTPUT_VIDEO"
        fi
    else
        echo "ffmpeg not found; skipping video generation."
    fi
else
    echo "No screenshot files found in $SCREENSHOT_DIR."
fi

echo "Screenshot daemon stopped."
