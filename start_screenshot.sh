#!/bin/bash

set -eu

# Stop any running screenshot daemon
pkill -f "screenshot_daemon.sh" || true

SCREENSHOT_DIR="/tmp/screenshots"
mkdir -p "$SCREENSHOT_DIR"
# Remove all previous screenshots before starting new session
rm -f "$SCREENSHOT_DIR"/*.png 2>/dev/null || true
chmod 777 "$SCREENSHOT_DIR"

# Create the background daemon script
cat << 'EOF' > /tmp/screenshot_daemon.sh
#!/bin/bash

SCREENSHOT_DIR="/tmp/screenshots"
mkdir -p "$SCREENSHOT_DIR"
chmod 777 "$SCREENSHOT_DIR"

while true; do
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    OUTFILE="$SCREENSHOT_DIR/screen_${TIMESTAMP}.png"

    # Find logged-in desktop GUI user (non-gdm)
    GUI_USER=$(ps aux | grep '[g]nome-shell' | grep -v 'gdm' | head -n 1 | awk '{print $1}')
    if [ -z "$GUI_USER" ]; then
        GUI_USER=$(who | grep -E '\(:[0-9]|tty[0-9]' | head -n 1 | awk '{print $1}')
    fi

    if [ -n "$GUI_USER" ]; then
        USER_UID=$(id -u "$GUI_USER" 2>/dev/null || echo "1000")
        BUS="unix:path=/run/user/$USER_UID/bus"
        RUNDIR="/run/user/$USER_UID"

        # Disable camera shutter / event sounds for the GUI session silently
        sudo -u "$GUI_USER" DBUS_SESSION_BUS_ADDRESS="$BUS" XDG_RUNTIME_DIR="$RUNDIR" gsettings set org.gnome.desktop.sound event-sounds false >/dev/null 2>&1 || true

        # Capture screenshot via gnome-screenshot as GUI_USER
        if command -v gnome-screenshot &> /dev/null; then
            sudo -u "$GUI_USER" DBUS_SESSION_BUS_ADDRESS="$BUS" XDG_RUNTIME_DIR="$RUNDIR" DISPLAY=":0" gnome-screenshot -f "$OUTFILE" >/dev/null 2>&1 || true
        fi

        # Fallback to scrot if gnome-screenshot didn't produce the image
        if [ ! -f "$OUTFILE" ] && command -v scrot &> /dev/null; then
            sudo -u "$GUI_USER" DISPLAY=":0" scrot -z "$OUTFILE" >/dev/null 2>&1 || true
        fi
    fi

    # Set permissions so any user can inspect the screenshot
    if [ -f "$OUTFILE" ]; then
        chmod 666 "$OUTFILE"
    fi

    sleep 5
done
EOF

chmod +x /tmp/screenshot_daemon.sh

# Run daemon in background
nohup /tmp/screenshot_daemon.sh > /tmp/screenshot_daemon.log 2>&1 &

echo "Cleaned previous screenshots and started silent screenshot daemon."
