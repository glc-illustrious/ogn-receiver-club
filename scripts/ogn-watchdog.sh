#!/bin/bash
# OGN receiver watchdog - checks WiFi connectivity and OGN processes
# Designed to run via cron every 5 minutes

LOG="/var/log/ogn-watchdog.log"
PING_TARGET="glidern1.glidernet.org"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | sudo tee -a "$LOG" > /dev/null
}

# Force-restart OGN service — kills all processes and starts fresh.
# Plain 'service rtlsdr-ogn restart' doesn't reliably kill ogn-rf (SUID root).
ogn_force_restart() {
    sudo service rtlsdr-ogn stop 2>/dev/null || true
    sleep 1
    sudo pkill -9 -f "ogn-rf" 2>/dev/null || true
    sudo pkill -9 -f "ogn-decode" 2>/dev/null || true
    sleep 2
    sudo rm -f /tmp/procServ-50000.pid /tmp/procServ-50001.pid /var/run/rtlsdr-ogn
    sudo service rtlsdr-ogn start
    sleep 10

    # Verify
    OGN_RF=$(pgrep -f "ogn-rf" || true)
    OGN_DECODE=$(pgrep -f "ogn-decode" || true)
    if [ -n "$OGN_RF" ] && [ -n "$OGN_DECODE" ]; then
        log "OK: OGN service restarted successfully"
    else
        log "ERROR: OGN service failed to restart"
    fi
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
    ogn_force_restart
    exit 0
fi

# Check OGN data pipeline health
# Both processes can be running while the data pipeline between them is broken
# (e.g. ogn-decode crashes and reconnects but can't read from ogn-rf).
# Detect this by checking for sustained zero decoded packets.
PIPELINE_STATE="/tmp/ogn-watchdog-pipeline"
PIPELINE_MAX_FAILURES=10  # minutes without traffic before restart

# Sample decoded packets from ogn-decode (2-second window)
PACKET_COUNT=$(timeout 3 sh -c '(sleep 2; printf "quit\r\n") | telnet localhost 50001 2>/dev/null' | grep -c 'dB/' 2>/dev/null || true)
[ -z "$PACKET_COUNT" ] && PACKET_COUNT=0

if [ "$PACKET_COUNT" -eq 0 ] 2>/dev/null; then
    FAIL_COUNT=0
    [ -f "$PIPELINE_STATE" ] && FAIL_COUNT=$(cat "$PIPELINE_STATE" 2>/dev/null || echo 0)
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "$FAIL_COUNT" > "$PIPELINE_STATE"

    if [ "$FAIL_COUNT" -ge "$PIPELINE_MAX_FAILURES" ]; then
        log "WARN: No decoded packets for ${FAIL_COUNT} minutes, force-restarting OGN service"
        echo "0" > "$PIPELINE_STATE"
        ogn_force_restart
    fi
else
    # Traffic is flowing, reset counter
    echo "0" > "$PIPELINE_STATE"
fi
