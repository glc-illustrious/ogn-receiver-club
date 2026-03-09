#!/bin/bash
# OGN Receiver installer for Raspberry Pi 4 running Debian 13 (trixie)
# Run as the 'pi' user: ./install.sh
#
# After installation, see CLAUDE.md for configuration and usage instructions.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== OGN Receiver Installer ==="
echo "Target: Raspberry Pi 4, Debian 13 (trixie)"
echo ""

# Check we're on a Pi
if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
    echo "WARNING: This doesn't appear to be a Raspberry Pi. Continuing anyway..."
fi

# Check we're not root (scripts expect to run as pi user)
if [ "$EUID" -eq 0 ]; then
    echo "ERROR: Do not run as root. Run as the 'pi' user."
    exit 1
fi

echo "--- Installing packages ---"
sudo apt-get update -q
sudo apt-get -y install rtl-sdr libconfig11 libjpeg-dev libfftw3-dev \
    lynx procserv telnet ntpsec overlayroot gh

echo ""
echo "--- Blacklisting DVB-T kernel modules ---"
sudo cp "$SCRIPT_DIR/configs/rtl-glidernet-blacklist.conf" /etc/modprobe.d/rtl-glidernet-blacklist.conf

echo ""
echo "--- Downloading OGN receiver binary ---"
cd /home/pi
wget -q http://download.glidernet.org/rpi-gpu/rtlsdr-ogn-bin-RPI-GPU-latest.tgz
tar xzf rtlsdr-ogn-bin-RPI-GPU-latest.tgz
rm rtlsdr-ogn-bin-RPI-GPU-latest.tgz

echo ""
echo "--- Setting up OGN receiver ---"
cd /home/pi/rtlsdr-ogn

# Create named pipe for IPC between ogn-rf and ogn-decode
[ -p ogn-rf.fifo ] || mkfifo ogn-rf.fifo

# SUID root for GPU access
sudo chown root gsm_scan ogn-rf
sudo chmod a+s gsm_scan ogn-rf

# Copy config template
cp "$SCRIPT_DIR/configs/MyReceiver.conf.template" MyReceiver.conf

# Download geoid separation data
bash getEGM.sh || echo "WARNING: Could not download geoid data (not critical)"

echo ""
echo "--- Installing service ---"
sudo wget -q http://download.glidernet.org/common/service/rtlsdr-ogn -O /etc/init.d/rtlsdr-ogn
sudo chmod +x /etc/init.d/rtlsdr-ogn

# Patch init script for Debian 13 ntpsec compatibility
sudo sed -i 's|service ntp stop|service ntpsec stop|g; s|service ntp start|service ntpsec start|g; s|/usr/sbin/ntp-wait|/usr/sbin/ntpwait|g' /etc/init.d/rtlsdr-ogn

# Service config
sudo tee /etc/rtlsdr-ogn.conf > /dev/null <<'EOF'
#port  user     directory                 command       args
50000  pi /home/pi/rtlsdr-ogn    ./ogn-rf     MyReceiver.conf
50001  pi /home/pi/rtlsdr-ogn    ./ogn-decode MyReceiver.conf
EOF

sudo update-rc.d rtlsdr-ogn defaults

echo ""
echo "--- Installing scripts ---"
mkdir -p /home/pi/scripts
cp "$SCRIPT_DIR/scripts/"*.sh /home/pi/scripts/
chmod +x /home/pi/scripts/*.sh

echo ""
echo "--- Setting up logrotate ---"
sudo cp "$SCRIPT_DIR/configs/ogn-receiver.logrotate" /etc/logrotate.d/ogn-receiver

echo ""
echo "--- Enabling hardware watchdog ---"
sudo sed -i 's/^#RuntimeWatchdogSec=off/RuntimeWatchdogSec=15/' /etc/systemd/system.conf 2>/dev/null || true
sudo sed -i 's/^#RebootWatchdogSec=10min/RebootWatchdogSec=3min/' /etc/systemd/system.conf 2>/dev/null || true

echo ""
echo "--- Setting up cron jobs ---"
(crontab -l 2>/dev/null | grep -v ogn; echo "*/5 * * * * /home/pi/scripts/ogn-watchdog.sh"; echo "0 4 * * 1 /home/pi/scripts/ogn-update.sh") | sort -u | crontab -

echo ""
echo "--- Setting WiFi regulatory domain to NL ---"
if ! grep -q "cfg80211.ieee80211_regdom=NL" /boot/firmware/cmdline.txt 2>/dev/null; then
    sudo sed -i 's/$/ cfg80211.ieee80211_regdom=NL/' /boot/firmware/cmdline.txt
fi

echo ""
echo "=== Installation complete ==="
echo ""
echo "Next steps:"
echo "  1. Reboot: sudo reboot"
echo "  2. Plug in RTL-SDR dongle"
echo "  3. Calibrate: cd ~/rtlsdr-ogn && ./gsm_scan --ppm 50 --gain 20"
echo "  4. Edit config: nano ~/rtlsdr-ogn/MyReceiver.conf"
echo "  5. Add club WiFi: ~/scripts/add-club-wifi.sh \"SSID\" \"password\""
echo "  6. Start service: sudo service rtlsdr-ogn start"
echo "  7. Enable SD card protection: ~/scripts/overlay-ctl.sh enable && sudo reboot"
echo ""
echo "See CLAUDE.md for full documentation."
