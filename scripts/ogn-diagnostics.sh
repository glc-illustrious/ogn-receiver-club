#!/bin/bash
# OGN diagnostics logger — runs every minute via cron
# Logs system health to help diagnose receiver dropouts
# Designed for field use on battery power (12V LiPo → 5V converter)

LOG="/var/log/ogn-diagnostics.log"

# Gather all metrics
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
UPTIME=$(awk '{printf "%.0f", $1}' /proc/uptime)

# CPU temperature
TEMP=$(vcgencmd measure_temp 2>/dev/null | grep -oP '[0-9.]+')

# Throttle flags — this is the key diagnostic for power issues
# Bit 0: under-voltage detected
# Bit 1: arm frequency capped
# Bit 2: currently throttled
# Bit 3: soft temperature limit active
# Bit 16: under-voltage has occurred (since boot)
# Bit 17: arm frequency capped has occurred
# Bit 18: throttling has occurred
# Bit 19: soft temperature limit has occurred
THROTTLE=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)

# Core voltage
VOLT=$(vcgencmd measure_volts core 2>/dev/null | grep -oP '[0-9.]+')

# CPU usage (1-min load avg vs cores)
LOAD=$(awk '{print $1}' /proc/loadavg)

# Memory
MEM_AVAIL=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo)

# WiFi signal strength (nmcli — iwconfig is not available on Debian 13)
WIFI_SSID=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes:' | cut -d: -f2)
WIFI_SIGNAL=$(nmcli -t -f active,signal dev wifi 2>/dev/null | grep '^yes:' | cut -d: -f2)

# USB devices (detect if RTL-SDR dongle disappeared)
USB_RTL=$(lsusb 2>/dev/null | grep -c -i "RTL2832\|RTL28\|0bda:2838\|0bda:2832")

# OGN processes
OGN_RF_PID=$(pgrep -f "ogn-rf" | head -1)
OGN_DEC_PID=$(pgrep -f "ogn-decode" | head -1)
OGN_RF_STATUS="DEAD"
OGN_DEC_STATUS="DEAD"
[ -n "$OGN_RF_PID" ] && OGN_RF_STATUS="ok($OGN_RF_PID)"
[ -n "$OGN_DEC_PID" ] && OGN_DEC_STATUS="ok($OGN_DEC_PID)"

# OGN decode traffic — sample decoded packets from ogn-decode telnet output
# The procserv log file is not populated, so we read directly from the telnet
# interface. Lines with 'dB/' are decoded OGN/FLARM packets.
APRS_LINES=0
if [ -n "$OGN_DEC_PID" ]; then
    APRS_LINES=$(timeout 3 sh -c '(sleep 2; printf "quit\r\n") | telnet localhost 50001 2>/dev/null' | grep -c 'dB/' 2>/dev/null || true)
    [ -z "$APRS_LINES" ] && APRS_LINES=0
fi

# Decode throttle flags into human-readable warnings
WARNINGS=""
if [ "$THROTTLE" != "0x0" ] && [ -n "$THROTTLE" ]; then
    THROT_DEC=$((THROTTLE))
    # Current flags (bits 0-3)
    [ $((THROT_DEC & 0x1)) -ne 0 ] && WARNINGS="${WARNINGS}UNDERVOLT "
    [ $((THROT_DEC & 0x2)) -ne 0 ] && WARNINGS="${WARNINGS}FREQ_CAP "
    [ $((THROT_DEC & 0x4)) -ne 0 ] && WARNINGS="${WARNINGS}THROTTLED "
    [ $((THROT_DEC & 0x8)) -ne 0 ] && WARNINGS="${WARNINGS}TEMP_LIMIT "
    # Historical flags since boot (bits 16-19)
    [ $((THROT_DEC & 0x10000)) -ne 0 ] && WARNINGS="${WARNINGS}PREV_UNDERVOLT "
    [ $((THROT_DEC & 0x20000)) -ne 0 ] && WARNINGS="${WARNINGS}PREV_FREQ_CAP "
    [ $((THROT_DEC & 0x40000)) -ne 0 ] && WARNINGS="${WARNINGS}PREV_THROTTLED "
    [ $((THROT_DEC & 0x80000)) -ne 0 ] && WARNINGS="${WARNINGS}PREV_TEMP_LIMIT "
fi

# Format: one line per minute, easy to grep/parse
echo "$TIMESTAMP | up=${UPTIME}s temp=${TEMP}C vcore=${VOLT}V throttle=$THROTTLE load=$LOAD mem=${MEM_AVAIL}MB | wifi=${WIFI_SSID:-NONE}(${WIFI_SIGNAL:-?}%) usb_rtl=$USB_RTL | rf=$OGN_RF_STATUS dec=$OGN_DEC_STATUS aprs=$APRS_LINES | ${WARNINGS:-OK}" >> "$LOG"
