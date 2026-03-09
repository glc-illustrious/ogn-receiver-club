#!/bin/bash
# Toggle the read-only overlay filesystem on/off
# Usage: overlay-ctl.sh enable|disable|status
# Requires reboot to take effect

set -e

CONF="/etc/overlayroot.conf"

case "$1" in
    enable)
        sudo sed -i 's/^overlayroot=.*/overlayroot="tmpfs"/' "$CONF"
        echo "Overlay enabled. Reboot to activate read-only mode."
        echo "Run: sudo reboot"
        ;;
    disable)
        sudo sed -i 's/^overlayroot=.*/overlayroot=""/' "$CONF"
        echo "Overlay disabled. Reboot to return to read-write mode."
        echo "Run: sudo reboot"
        ;;
    status)
        if mount | grep -q "overlayroot"; then
            echo "ACTIVE: Root filesystem is read-only with RAM overlay"
            echo "Writes go to RAM and are lost on reboot."
            df -h / /media/root-ro 2>/dev/null
        else
            echo "INACTIVE: Root filesystem is read-write (normal mode)"
        fi
        ;;
    *)
        echo "Usage: $0 {enable|disable|status}"
        echo ""
        echo "  enable  - Enable read-only overlay (takes effect after reboot)"
        echo "  disable - Disable overlay (takes effect after reboot)"
        echo "  status  - Show current overlay state"
        echo ""
        echo "When overlay is active, the real root is at /media/root-ro"
        exit 1
        ;;
esac
