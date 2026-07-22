#!/bin/bash

set -eu

# Stop systemd service cleanly
systemctl stop screenshot-daemon.service || true

SCREENSHOT_DIR="/var/screenshots"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_VIDEO="/var/screenshots/contest_session_${TIMESTAMP}.mp4"
PERMANENT_LINK="/var/screenshots/contest_session_latest.mp4"

if [ -d "$SCREENSHOT_DIR" ] && compgen -G "$SCREENSHOT_DIR/*.png" > /dev/null; then
    echo "Creating permanent MP4 video from captured screenshots..."

    if command -v ffmpeg &> /dev/null; then
        ffmpeg -framerate 2 -pattern_type glob -i "$SCREENSHOT_DIR/*.png" \
               -c:v libx264 -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -pix_fmt yuv420p "$OUTPUT_VIDEO" -y >/dev/null 2>&1 || true
        if [ -f "$OUTPUT_VIDEO" ]; then
            chown root:root "$OUTPUT_VIDEO"
            chmod 644 "$OUTPUT_VIDEO"
            ln -sf "$OUTPUT_VIDEO" "$PERMANENT_LINK" || true
            echo "Permanent video created successfully at: $OUTPUT_VIDEO"
            echo "Latest video symlink updated at: $PERMANENT_LINK"
        fi
    else
        echo "ffmpeg not found; skipping video generation."
    fi
else
    echo "No screenshot files found in $SCREENSHOT_DIR."
fi

echo "Screenshot daemon stopped."
