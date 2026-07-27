#!/bin/bash

# Do NOT set -e so fallback commands can fail gracefully without crashing the daemon loop

SCREENSHOT_DIR="/var/screenshots"
mkdir -p "$SCREENSHOT_DIR"
chmod 1777 "$SCREENSHOT_DIR"

while true; do
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    OUTFILE="$SCREENSHOT_DIR/screen_${TIMESTAMP}.png"

    # Find active logged-in desktop GUI user on seat0
    GUI_USER=""
    if command -v loginctl &>/dev/null; then
        GUI_USER=$(loginctl list-sessions --no-legend 2>/dev/null | grep 'seat0' | awk '{print $3}' | grep -v -E 'root|gdm' | head -n1 || true)
    fi
    if [ -z "$GUI_USER" ]; then
        GUI_USER=$(ps aux | grep '[g]nome-shell' | grep -v 'gdm' | head -n 1 | awk '{print $1}' || true)
    fi
    if [ -z "$GUI_USER" ]; then
        GUI_USER=$(ps aux | grep -E '[x]fce4-session|[m]ate-session|[c]innamon|[k]win|[w]ayland' | head -n 1 | awk '{print $1}' || true)
    fi
    if [ -z "$GUI_USER" ]; then
        GUI_USER=$(who | grep -E '\(:[0-9]|tty[0-9]' | head -n 1 | awk '{print $1}' || true)
    fi

    if [ -n "$GUI_USER" ]; then
        USER_UID=$(id -u "$GUI_USER" 2>/dev/null || echo "1000")
        BUS="unix:path=/run/user/$USER_UID/bus"
        RUNDIR="/run/user/$USER_UID"

        # Determine DISPLAY variable for X11 fallback compatibility
        DISP=":0"
        USER_DISP=$(ps aux -u "$GUI_USER" | grep -o 'DISPLAY=:[0-9]' | head -n 1 | cut -d= -f2 || true)
        if [ -n "$USER_DISP" ]; then
            DISP="$USER_DISP"
        fi

        # 1. Mute event sounds and disable screen flash animations in GNOME 46 (Ubuntu 24.04 Wayland)
        sudo -u "$GUI_USER" DBUS_SESSION_BUS_ADDRESS="$BUS" XDG_RUNTIME_DIR="$RUNDIR" \
            gsettings set org.gnome.desktop.interface enable-animations false >/dev/null 2>&1 || true
        sudo -u "$GUI_USER" DBUS_SESSION_BUS_ADDRESS="$BUS" XDG_RUNTIME_DIR="$RUNDIR" \
            gsettings set org.gnome.desktop.sound event-sounds false >/dev/null 2>&1 || true
        sudo -u "$GUI_USER" DBUS_SESSION_BUS_ADDRESS="$BUS" XDG_RUNTIME_DIR="$RUNDIR" \
            gsettings set org.gnome.gnome-screenshot enable-sound false >/dev/null 2>&1 || true

        # 2. GNOME 46 Wayland Native Method A: GNOME Shell D-Bus Screenshot (Full Screen, flash=false)
        if command -v gdbus &> /dev/null; then
            sudo -u "$GUI_USER" DBUS_SESSION_BUS_ADDRESS="$BUS" XDG_RUNTIME_DIR="$RUNDIR" \
                gdbus call --session \
                           --dest org.gnome.Shell.Screenshot \
                           --object-path /org/gnome/Shell/Screenshot \
                           --method org.gnome.Shell.Screenshot.Screenshot \
                           false false "$OUTFILE" >/dev/null 2>&1 || true
        fi

        # 3. GNOME 46 Wayland Native Method B: GNOME Shell D-Bus ScreenshotArea (flash=false)
        if [ ! -f "$OUTFILE" ] || [ $(stat -c%s "$OUTFILE" 2>/dev/null || echo 0) -lt 10000 ]; then
            rm -f "$OUTFILE" 2>/dev/null || true
            if command -v gdbus &> /dev/null; then
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
        fi

        # 4. Fallback Method C: gnome-screenshot CLI
        if [ ! -f "$OUTFILE" ] || [ $(stat -c%s "$OUTFILE" 2>/dev/null || echo 0) -lt 10000 ]; then
            rm -f "$OUTFILE" 2>/dev/null || true
            if command -v gnome-screenshot &> /dev/null; then
                sudo -u "$GUI_USER" DBUS_SESSION_BUS_ADDRESS="$BUS" XDG_RUNTIME_DIR="$RUNDIR" DISPLAY="$DISP" gnome-screenshot -f "$OUTFILE" >/dev/null 2>&1 || true
            fi
        fi

        # 5. Fallback Method D: ffmpeg x11grab (X11 sessions)
        if [ ! -f "$OUTFILE" ] || [ $(stat -c%s "$OUTFILE" 2>/dev/null || echo 0) -lt 10000 ]; then
            rm -f "$OUTFILE" 2>/dev/null || true
            if command -v ffmpeg &> /dev/null; then
                sudo -u "$GUI_USER" DISPLAY="$DISP" ffmpeg -y -loglevel quiet -f x11grab -i "$DISP" -vframes 1 "$OUTFILE" >/dev/null 2>&1 || true
            fi
        fi

        # Clean up any empty or black images (<10KB)
        if [ -f "$OUTFILE" ] && [ $(stat -c%s "$OUTFILE" 2>/dev/null || echo 0) -lt 10000 ]; then
            rm -f "$OUTFILE" 2>/dev/null || true
        fi
    fi

    # Lock root ownership so sticky bit (+t / 1777) prevents contestant deletion
    if [ -f "$OUTFILE" ]; then
        chown root:root "$OUTFILE"
        chmod 644 "$OUTFILE"
    fi

    sleep 5
done
