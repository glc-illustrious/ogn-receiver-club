#!/bin/bash
# Auto-update OGN receiver binary
# Compares local version against latest download, updates if different
# Designed to run via cron weekly

set -e

LOG="/var/log/ogn-watchdog.log"
OGN_DIR="/home/pi/rtlsdr-ogn"
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" = "arm64" ]; then
    TGZ_URL="http://download.glidernet.org/arm64/rtlsdr-ogn-bin-arm64-latest.tgz"
else
    TGZ_URL="http://download.glidernet.org/rpi-gpu/rtlsdr-ogn-bin-RPI-GPU-latest.tgz"
fi
TMP_DIR=$(mktemp -d)

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [update] $1" | sudo tee -a "$LOG" > /dev/null
}

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Download latest
if ! wget -q "$TGZ_URL" -O "$TMP_DIR/latest.tgz"; then
    log "ERROR: Failed to download latest OGN binary"
    exit 1
fi

# Extract to temp — find the extracted directory name
tar xzf "$TMP_DIR/latest.tgz" -C "$TMP_DIR"
EXTRACT_DIR=$(find "$TMP_DIR" -maxdepth 1 -type d -name 'rtlsdr-ogn*' | head -1)
if [ -z "$EXTRACT_DIR" ]; then
    log "ERROR: Could not find extracted OGN directory"
    exit 1
fi

# Compare ogn-decode binary (if identical, no update needed)
if cmp -s "$EXTRACT_DIR/ogn-decode" "$OGN_DIR/ogn-decode"; then
    log "OK: OGN binary is already up to date"
    exit 0
fi

log "INFO: New OGN binary found, updating..."

# Stop service
sudo service rtlsdr-ogn stop
sleep 2

# Backup current install
BACKUP="/home/pi/rtlsdr-ogn.backup-$(date +%Y%m%d)"
cp -a "$OGN_DIR" "$BACKUP"

# Copy new binaries (preserve config, fifo, and geoid data)
for f in ogn-rf ogn-decode gsm_scan; do
    cp "$EXTRACT_DIR/$f" "$OGN_DIR/$f"
done

# Copy other updated files (not config)
for f in Changelog INSTALL Template.conf rtlsdr-ogn; do
    if [ -f "$EXTRACT_DIR/$f" ]; then
        cp "$EXTRACT_DIR/$f" "$OGN_DIR/$f"
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
