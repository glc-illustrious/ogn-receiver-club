# OGN Receiver for Raspberry Pi

Automated setup for an [Open Glider Network](https://www.glidernet.org/) receiver on a Raspberry Pi 4 running Debian 13 (trixie).

Receives FLARM/OGN/FANET/PilotAware signals via an RTL-SDR USB dongle and forwards aircraft positions to the OGN APRS network.

## Quick Start

On a fresh Raspberry Pi OS (Debian 13 / trixie):

```bash
git clone https://github.com/YOUR_ORG/ogn-receiver.git
cd ogn-receiver
./install.sh
sudo reboot
```

Then at the airfield:

```bash
# Calibrate the RTL-SDR dongle
cd ~/rtlsdr-ogn && ./gsm_scan --ppm 50 --gain 20

# Edit config with your location, callsign, and frequency correction
nano ~/rtlsdr-ogn/MyReceiver.conf

# Connect to club WiFi
~/scripts/add-club-wifi.sh "ClubSSID" "password"

# Start the receiver
sudo service rtlsdr-ogn start

# Lock down the SD card for unattended operation
~/scripts/overlay-ctl.sh enable && sudo reboot
```

## What's Included

| Component | Description |
|---|---|
| `install.sh` | One-command installer for a fresh Pi |
| `scripts/ogn-watchdog.sh` | Monitors WiFi, Tailscale, and OGN processes (cron, every 5 min) |
| `scripts/ogn-update.sh` | Auto-updates OGN binaries with rollback (cron, weekly) |
| `scripts/add-club-wifi.sh` | Helper to add WiFi networks |
| `scripts/overlay-ctl.sh` | Enable/disable read-only SD card protection |
| `configs/` | Template configs for the receiver, kernel blacklist, and logrotate |

## Reliability Features

- **Hardware watchdog**: Auto-reboots on kernel/systemd hang (BCM2835, 15s timeout)
- **Process watchdog**: Restarts OGN receiver if ogn-rf or ogn-decode dies
- **WiFi watchdog**: Reconnects WiFi if connectivity is lost
- **Tailscale watchdog**: Restarts Tailscale for remote access
- **Read-only SD card**: Overlay filesystem prevents corruption from power loss
- **Auto-update**: Weekly binary updates with automatic rollback on failure

## Debian 13 (Trixie) Notes

The [OGN wiki guide](http://wiki.glidernet.org/wiki:manual-installation-guide) targets older Debian. This installer handles the necessary adaptations:

- `libconfig9` → `libconfig11`
- `libjpeg8` → `libjpeg-dev`
- `ntp` → `ntpsec` (init script patched accordingly)

## Architecture

```
RTL-SDR dongle → ogn-rf (port 50000) → ogn-rf.fifo → ogn-decode (port 50001) → APRS network
```

See [CLAUDE.md](CLAUDE.md) for detailed documentation.

## License

Scripts and configs in this repo are provided as-is for the gliding community. OGN receiver binaries are from [glidernet.org](https://www.glidernet.org/).
