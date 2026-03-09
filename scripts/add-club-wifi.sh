#!/bin/bash
# Add a WiFi network to the Pi
# Usage: ./add-club-wifi.sh "SSID" "password"
#        ./add-club-wifi.sh  (interactive)

set -e

if [ -n "$1" ]; then
    SSID="$1"
    PASS="$2"
else
    read -rp "WiFi SSID: " SSID
    read -rsp "WiFi password: " PASS
    echo
fi

if [ -z "$SSID" ]; then
    echo "Error: SSID is required"
    exit 1
fi

if [ -z "$PASS" ]; then
    echo "Connecting to open network '$SSID'..."
    sudo nmcli device wifi connect "$SSID"
else
    echo "Connecting to '$SSID'..."
    sudo nmcli device wifi connect "$SSID" password "$PASS"
fi

echo "Done. Current connection:"
nmcli -t -f active,ssid dev wifi | grep '^yes'
