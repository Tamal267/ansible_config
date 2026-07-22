#!/bin/bash

set -eu

# Stop any running screenshot daemon
pkill -f "screenshot_daemon.sh" || true

SCREENSHOT_DIR="/var/screenshots"
mkdir -p "$SCREENSHOT_DIR"
# Clean previous screenshots safely
rm -f "$SCREENSHOT_DIR"/*.png 2>/dev/null || true

# Set sticky bit (+t / 1777) so users can write new PNGs, but CANNOT delete root-owned files
chmod 1777 "$SCREENSHOT_DIR"

# Create the background daemon script in protected system path
cat << 'EOF' > /usr/local/bin/screenshot_daemon.sh
#!/bin/bash

SCREENSHOT_DIR="/var/screenshots"
mkdir -p "$SCREENSHOT_DIR"
chmod 1777 "$SCREENSHOT_DIR"

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

        # 1. Primary: Native GNOME Shell DBus API (Silent, No Flash, Works on Wayland & X11)
        if command -v gdbus &> /dev/null; then
            sudo -u "$GUI_USER" DBUS_SESSION_BUS_ADDRESS="$BUS" XDG_RUNTIME_DIR="$RUNDIR" \
                gdbus call --session \
                           --dest org.gnome.Shell.Screenshot \
                           --object-path /org/gnome/Shell/Screenshot \
                           --method org.gnome.Shell.Screenshot.Screenshot \
                           false false "$OUTFILE" >/dev/null 2>&1 || true
        fi

        # 2. Fallback: gnome-screenshot tool
        if [ ! -f "$OUTFILE" ] && command -v gnome-screenshot &> /dev/null; then
            sudo -u "$GUI_USER" DBUS_SESSION_BUS_ADDRESS="$BUS" XDG_RUNTIME_DIR="$RUNDIR" DISPLAY=":0" gnome-screenshot -f "$OUTFILE" >/dev/null 2>&1 || true
        fi

        # 3. Fallback: scrot
        if [ ! -f "$OUTFILE" ] && command -v scrot &> /dev/null; then
            sudo -u "$GUI_USER" DISPLAY=":0" scrot -z "$OUTFILE" >/dev/null 2>&1 || true
        fi
    fi

    # Instantly set root ownership so sticky bit prevents non-root deletion
    if [ -f "$OUTFILE" ]; then
        chown root:root "$OUTFILE"
        chmod 644 "$OUTFILE"
    fi

    sleep 5
done
EOF

chmod 755 /usr/local/bin/screenshot_daemon.sh

# Run daemon in background
nohup /usr/local/bin/screenshot_daemon.sh > /var/log/screenshot_daemon.log 2>&1 &

echo "Cleaned previous screenshots and started silent screenshot daemon in protected path (/var/screenshots)."
