#!/bin/bash

set -eu

SCREENSHOT_DIR="/var/screenshots"
mkdir -p "$SCREENSHOT_DIR"
chmod 1777 "$SCREENSHOT_DIR"

while true; do
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    OUTFILE="$SCREENSHOT_DIR/screen_${TIMESTAMP}.png"

    # Find logged-in desktop GUI user (non-gdm)
    GUI_USER=$(ps aux | grep '[g]nome-shell' | grep -v 'gdm' | head -n 1 | awk '{print $1}')
    if [ -z "$GUI_USER" ]; then
        GUI_USER=$(ps aux | grep -E '[x]fce4-session|[m]ate-session|[c]innamon|[k]win|[w]ayland' | head -n 1 | awk '{print $1}')
    fi
    if [ -z "$GUI_USER" ]; then
        GUI_USER=$(who | grep -E '\(:[0-9]|tty[0-9]' | head -n 1 | awk '{print $1}')
    fi

    if [ -n "$GUI_USER" ]; then
        USER_UID=$(id -u "$GUI_USER" 2>/dev/null || echo "1000")
        BUS="unix:path=/run/user/$USER_UID/bus"
        RUNDIR="/run/user/$USER_UID"

        # Determine DISPLAY variable for the user
        DISP=":0"
        USER_DISP=$(ps aux -u "$GUI_USER" | grep -o 'DISPLAY=:[0-9]' | head -n 1 | cut -d= -f2 || true)
        if [ -n "$USER_DISP" ]; then
            DISP="$USER_DISP"
        fi

        # 1. Disable shutter sound and event sounds in GNOME 46 (Ubuntu 24.04)
        sudo -u "$GUI_USER" DBUS_SESSION_BUS_ADDRESS="$BUS" XDG_RUNTIME_DIR="$RUNDIR" \
            gsettings set org.gnome.desktop.sound event-sounds false >/dev/null 2>&1 || true
        sudo -u "$GUI_USER" DBUS_SESSION_BUS_ADDRESS="$BUS" XDG_RUNTIME_DIR="$RUNDIR" \
            gsettings set org.gnome.gnome-screenshot enable-sound false >/dev/null 2>&1 || true

        # 2. Ubuntu 24.04 Method A: ffmpeg x11grab (100% Silent, Zero Flash, Zero Shutter Sound)
        if command -v ffmpeg &> /dev/null; then
            sudo -u "$GUI_USER" DISPLAY="$DISP" ffmpeg -y -loglevel quiet -f x11grab -i "$DISP" -vframes 1 "$OUTFILE" >/dev/null 2>&1 || true
        fi

        # 3. Ubuntu 24.04 Method B: ImageMagick import (100% Silent, Zero Flash)
        if [ ! -f "$OUTFILE" ] && command -v import &> /dev/null; then
            sudo -u "$GUI_USER" DISPLAY="$DISP" import -window root "$OUTFILE" >/dev/null 2>&1 || true
        fi

        # 4. Ubuntu 24.04 Method C: xwd (Native X11 Dump, 100% Silent)
        if [ ! -f "$OUTFILE" ] && command -v xwd &> /dev/null && command -v convert &> /dev/null; then
            sudo -u "$GUI_USER" DISPLAY="$DISP" xwd -root -silent | convert xwd:- "$OUTFILE" >/dev/null 2>&1 || true
        fi

        # 5. Ubuntu 24.04 Method D: GNOME Shell D-Bus ScreenshotArea (with dynamic screen resolution)
        if [ ! -f "$OUTFILE" ] && command -v gdbus &> /dev/null; then
            # Get actual monitor resolution or default to 1920x1080
            SW=1920
            SH=1080
            RES=$(sudo -u "$GUI_USER" DISPLAY="$DISP" xrandr 2>/dev/null | grep '*' | head -n1 | awk '{print $1}' || true)
            if [ -n "$RES" ]; then
                SW=$(echo "$RES" | cut -dx -f1)
                SH=$(echo "$RES" | cut -dx -f2)
            fi

            sudo -u "$GUI_USER" DBUS_SESSION_BUS_ADDRESS="$BUS" XDG_RUNTIME_DIR="$RUNDIR" \
                gdbus call --session \
                           --dest org.gnome.Shell.Screenshot \
                           --object-path /org/gnome/Shell/Screenshot \
                           --method org.gnome.Shell.Screenshot.ScreenshotArea \
                           0 0 "$SW" "$SH" false "$OUTFILE" >/dev/null 2>&1 || true
        fi

        # 6. Ubuntu 24.04 Method E: Fallback gnome-screenshot (with sound muted via GSettings)
        if [ ! -f "$OUTFILE" ] && command -v gnome-screenshot &> /dev/null; then
            sudo -u "$GUI_USER" DBUS_SESSION_BUS_ADDRESS="$BUS" XDG_RUNTIME_DIR="$RUNDIR" DISPLAY="$DISP" gnome-screenshot -f "$OUTFILE" >/dev/null 2>&1 || true
        fi
    fi

    # Lock root ownership so sticky bit (+t / 1777) prevents contestant deletion
    if [ -f "$OUTFILE" ]; then
        chown root:root "$OUTFILE"
        chmod 644 "$OUTFILE"
    fi

    sleep 5
done
