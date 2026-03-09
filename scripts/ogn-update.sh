#!/bin/bash
# Auto-update OGN receiver binary
# Compares local version against latest download, updates if different
# Designed to run via cron weekly

set -e

LOG="/var/log/ogn-watchdog.log"
OGN_DIR="/home/pi/rtlsdr-ogn"
TGZ_URL="http://download.glidernet.org/rpi-gpu/rtlsdr-ogn-bin-RPI-GPU-latest.tgz"
TMP_DIR=$(mktemp -d)
OVERLAY_ACTIVE=false

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [update] $1" | sudo tee -a "$LOG" > /dev/null
}

cleanup() {
    rm -rf "$TMP_DIR"
    # Re-enable overlay if we disabled it
    if [ "$OVERLAY_ACTIVE" = true ]; then
        sudo sed -i 's/^overlayroot=.*/overlayroot="tmpfs"/' /etc/overlayroot.conf
    fi
}
trap cleanup EXIT

# If overlay is active, we need to write to the real root
if mount | grep -q "overlayroot"; then
    OVERLAY_ACTIVE=true
    OGN_DIR="/media/root-ro/home/pi/rtlsdr-ogn"
fi

# Download latest
if ! wget -q "$TGZ_URL" -O "$TMP_DIR/latest.tgz"; then
    log "ERROR: Failed to download latest OGN binary"
    exit 1
fi

# Extract to temp
tar xzf "$TMP_DIR/latest.tgz" -C "$TMP_DIR"

# Compare ogn-decode binary (if identical, no update needed)
if cmp -s "$TMP_DIR/rtlsdr-ogn/ogn-decode" "$OGN_DIR/ogn-decode"; then
    log "OK: OGN binary is already up to date"
    exit 0
fi

log "INFO: New OGN binary found, updating..."

# Stop service
sudo service rtlsdr-ogn stop
sleep 2

# If overlay is active, remount the real root read-write
if [ "$OVERLAY_ACTIVE" = true ]; then
    sudo mount -o remount,rw /media/root-ro
fi

# Backup current install
BACKUP="${OGN_DIR}.backup-$(date +%Y%m%d)"
cp -a "$OGN_DIR" "$BACKUP"

# Copy new binaries (preserve config, fifo, and geoid data)
for f in ogn-rf ogn-decode gsm_scan; do
    cp "$TMP_DIR/rtlsdr-ogn/$f" "$OGN_DIR/$f"
done

# Copy other updated files (not config)
for f in Changelog INSTALL Template.conf rtlsdr-ogn; do
    if [ -f "$TMP_DIR/rtlsdr-ogn/$f" ]; then
        cp "$TMP_DIR/rtlsdr-ogn/$f" "$OGN_DIR/$f"
    fi
done

# Restore permissions for GPU usage
sudo chown root "$OGN_DIR/gsm_scan" "$OGN_DIR/ogn-rf"
sudo chmod a+s "$OGN_DIR/gsm_scan" "$OGN_DIR/ogn-rf"

# Restart service
sudo service rtlsdr-ogn start
sleep 10

# Verify
OGN_RF=$(pgrep -f "ogn-rf" || true)
OGN_DECODE=$(pgrep -f "ogn-decode" || true)
if [ -n "$OGN_RF" ] && [ -n "$OGN_DECODE" ]; then
    log "OK: OGN updated and restarted successfully (backup: $BACKUP)"
else
    log "ERROR: OGN failed to start after update, rolling back"
    cp -a "$BACKUP"/* "$OGN_DIR/"
    sudo chown root "$OGN_DIR/gsm_scan" "$OGN_DIR/ogn-rf"
    sudo chmod a+s "$OGN_DIR/gsm_scan" "$OGN_DIR/ogn-rf"
    sudo service rtlsdr-ogn start
    log "INFO: Rolled back to previous version"
fi

# If overlay is active, remount real root back to read-only and reboot
# so the overlay picks up the new binaries
if [ "$OVERLAY_ACTIVE" = true ]; then
    sudo mount -o remount,ro /media/root-ro
    log "INFO: Rebooting to apply update under overlay"
    sudo reboot
fi
