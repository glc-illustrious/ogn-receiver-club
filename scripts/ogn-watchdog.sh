#!/bin/bash
# OGN receiver watchdog - checks WiFi connectivity and OGN processes
# Designed to run via cron every 5 minutes

LOG="/var/log/ogn-watchdog.log"
PING_TARGET="glidern1.glidernet.org"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | sudo tee -a "$LOG" > /dev/null
}

# Check WiFi connectivity
if ! ping -c 2 -W 5 "$PING_TARGET" > /dev/null 2>&1; then
    log "WARN: No connectivity to $PING_TARGET"

    # Check if wlan0 is associated
    if ! iwconfig wlan0 2>/dev/null | grep -q "ESSID:\""; then
        log "WARN: WiFi not associated, attempting reconnect"
        sudo nmcli device wifi rescan 2>/dev/null
        sleep 2
        sudo nmcli device connect wlan0 2>/dev/null
        sleep 5
    fi

    # Re-check after reconnect attempt
    if ! ping -c 2 -W 5 8.8.8.8 > /dev/null 2>&1; then
        log "ERROR: Still no connectivity after reconnect attempt"
    else
        log "OK: Connectivity restored"
    fi
fi

# Check Tailscale
if ! tailscale status > /dev/null 2>&1; then
    log "WARN: Tailscale is down, restarting"
    sudo systemctl restart tailscaled
    sleep 5
    if tailscale status > /dev/null 2>&1; then
        log "OK: Tailscale restored"
    else
        log "ERROR: Tailscale failed to restart"
    fi
fi

# Check OGN processes
OGN_RF=$(pgrep -f "ogn-rf" || true)
OGN_DECODE=$(pgrep -f "ogn-decode" || true)

if [ -z "$OGN_RF" ] || [ -z "$OGN_DECODE" ]; then
    log "WARN: OGN process missing (ogn-rf: ${OGN_RF:-DEAD}, ogn-decode: ${OGN_DECODE:-DEAD}), restarting service"
    sudo service rtlsdr-ogn restart
    sleep 10

    # Verify restart
    OGN_RF=$(pgrep -f "ogn-rf" || true)
    OGN_DECODE=$(pgrep -f "ogn-decode" || true)
    if [ -n "$OGN_RF" ] && [ -n "$OGN_DECODE" ]; then
        log "OK: OGN service restarted successfully"
    else
        log "ERROR: OGN service failed to restart"
    fi
fi
