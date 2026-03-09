# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Raspberry Pi 4 (aarch64) running Debian 13 (trixie) configured as an **OGN (Open Glider Network) receiver** for a gliding club. It receives ADS-B/FLARM/OGN signals via an RTL-SDR USB dongle and forwards them to the OGN APRS network.

## Remote Access

Tailscale is installed for remote management. The Pi is reachable at `<TAILSCALE_IP>` (hostname: `pi`) from any device on the tailnet, even behind the club's NAT. SSH in with `ssh pi@<TAILSCALE_IP>`.

Useful commands:
- `tailscale status` — show tailnet peers
- `sudo systemctl restart tailscaled` — restart if Tailscale goes down (the watchdog does this automatically)

## Key Paths

- **OGN receiver binaries**: `/home/pi/rtlsdr-ogn/` (ogn-rf, ogn-decode, gsm_scan)
- **Receiver config**: `/home/pi/rtlsdr-ogn/MyReceiver.conf` — edit this with location, callsign, frequency correction
- **Service config**: `/etc/rtlsdr-ogn.conf` — maps ports 50000/50001 to ogn-rf/ogn-decode processes
- **Init script**: `/etc/init.d/rtlsdr-ogn` — patched for ntpsec (Debian 13 uses ntpsec, not ntp)
- **Kernel blacklist**: `/etc/modprobe.d/rtl-glidernet-blacklist.conf` — prevents DVB-T drivers from claiming the dongle
- **Watchdog script**: `/home/pi/scripts/ogn-watchdog.sh` — checks WiFi and OGN processes every minute (cron)
- **Diagnostics logger**: `/home/pi/scripts/ogn-diagnostics.sh` — logs system health every minute (temp, voltage, throttle, USB, WiFi, OGN)
- **WiFi helper**: `/home/pi/scripts/add-club-wifi.sh` — add WiFi networks easily
- **Auto-update script**: `/home/pi/scripts/ogn-update.sh` — weekly OGN binary update (cron, Monday 4am)
- **Watchdog log**: `/var/log/ogn-watchdog.log` (also used by update script)
- **Diagnostics log**: `/var/log/ogn-diagnostics.log` — per-minute system health
- **Logrotate config**: `/etc/logrotate.d/ogn-receiver`
- **Overlay control**: `/home/pi/scripts/overlay-ctl.sh` — enable/disable read-only SD card protection
- **Overlay config**: `/etc/overlayroot.conf` — set `overlayroot="tmpfs"` to enable

## Common Commands

```bash
# Start/stop/restart the OGN receiver service
sudo service rtlsdr-ogn start
sudo service rtlsdr-ogn stop
sudo service rtlsdr-ogn restart

# View live RF reception output
telnet localhost 50000

# View live APRS data traffic
telnet localhost 50001

# Calibrate frequency with GSM scan (service must be stopped first)
sudo service rtlsdr-ogn stop
cd /home/pi/rtlsdr-ogn && ./gsm_scan --ppm 50 --gain 20

# Check service status
sudo service rtlsdr-ogn status

# Add a WiFi network (e.g. at the club)
/home/pi/scripts/add-club-wifi.sh "ClubSSID" "password"

# View watchdog log
cat /var/log/ogn-watchdog.log
```

## Setup Steps Still Required

1. **Plug in RTL-SDR dongle** and reboot (kernel blacklist takes effect on reboot)
2. **Run `gsm_scan`** to determine the crystal frequency correction (ppm) and find a good GSM calibration frequency
3. **Edit `/home/pi/rtlsdr-ogn/MyReceiver.conf`**:
   - Set `FreqCorr` to the measured ppm value
   - Set `GSM.CenterFreq` to the strongest GSM frequency found
   - Set `Position.Latitude`, `Position.Longitude`, `Position.Altitude` for the airfield
   - Uncomment and set `APRS.Call` to the receiver name (max 9 chars, typically ICAO airfield code)
   - For Americas/Israel: add `FreqPlan = 2;` in the RF block
4. **Start the service**: `sudo service rtlsdr-ogn start`
5. **Register the receiver** on the OGN receiver list at http://wiki.glidernet.org/receiver-naming-convention

## Architecture

The OGN receiver runs as two cooperating processes managed by `procserv`:

```
RTL-SDR dongle → ogn-rf (port 50000) → ogn-rf.fifo (named pipe) → ogn-decode (port 50001) → APRS network
```

- **ogn-rf**: Interfaces with the RTL-SDR hardware, performs RF reception and GSM-based frequency calibration. Runs with SUID root for GPU access on Pi.
- **ogn-decode**: Reads IQ samples from the FIFO, demodulates FLARM/OGN/FANET/PilotAware packets, and forwards positions to the OGN APRS server.
- **procserv**: Wraps each process with a telnet-accessible console (ports 50000/50001) for monitoring.
- **ntpsec**: Provides time synchronization — the service waits for NTP sync before starting (can take up to 30 min on cold boot).

## Debian 13 (Trixie) Specifics

The OGN wiki guide targets older Debian versions. Adaptations made for trixie:

- `libconfig9` → `libconfig11`
- `libjpeg8` → `libjpeg-dev` (or build libjpeg8 from source per wiki workaround)
- `ntp` → `ntpsec` (provides `ntpwait` at `/usr/sbin/ntpwait` instead of `ntp-wait`)
- Init script patched: `service ntp` → `service ntpsec`, `ntp-wait` → `ntpwait`

## RTL-SDR V3 Dongle (if applicable)

If using the RTL-SDR.com V3 dongle with bias-T for powering a preamp:
1. Build the custom rtl-sdr driver from https://github.com/rtlsdrblog/rtl-sdr-blog
2. Remove the system rtl-sdr package first: `sudo apt-get remove --purge rtl-sdr`
3. Add `BiasTee = 1;` to the RF section of MyReceiver.conf

## Watchdog Setup

Four layers of reliability:

1. **Hardware watchdog** (BCM2835): systemd pets the hardware watchdog every 15s. If systemd or the kernel hangs, the Pi auto-reboots. Configured in `/etc/systemd/system.conf` (`RuntimeWatchdogSec=15`, `RebootWatchdogSec=3min`). Takes effect on next boot.

2. **WiFi watchdog** (`/home/pi/scripts/ogn-watchdog.sh`, cron every minute): Pings `glidern1.glidernet.org`, reconnects WiFi via NetworkManager if unreachable.

3. **Tailscale watchdog** (same script): Checks `tailscale status`, restarts `tailscaled` service if down.

4. **OGN process watchdog** (same script): Checks that ogn-rf and ogn-decode are running, restarts the service if either dies.

Cron entries (pi user):
- `* * * * * /home/pi/scripts/ogn-watchdog.sh`
- `* * * * * /home/pi/scripts/ogn-diagnostics.sh`
- `0 4 * * 1 /home/pi/scripts/ogn-update.sh`

**Diagnostics** (`ogn-diagnostics.sh`): Logs every minute to `/var/log/ogn-diagnostics.log`. Each line records: CPU temp, core voltage, throttle flags (undervoltage/thermal), CPU load, free memory, WiFi signal strength, USB dongle presence, OGN process status, and APRS traffic count. Key for diagnosing dropouts on battery power — look for `UNDERVOLT` or `usb_rtl=0` entries.

**Log rotation**: Handled by logrotate (`/etc/logrotate.d/ogn-receiver`). Rotates weekly, keeps 4 weeks compressed. Covers `/var/log/ogn-watchdog.log`, `/var/log/ogn-diagnostics.log`, and OGN procserv logs in `/var/log/rtlsdr-ogn/`.

**Auto-update** (`ogn-update.sh`): Runs weekly Monday 4am. Downloads the latest RPI-GPU binary from `download.glidernet.org`, compares against installed version, and updates if changed. Creates a timestamped backup (`/home/pi/rtlsdr-ogn.backup-YYYYMMDD`) before updating. Automatically rolls back if the service fails to start after update. Preserves `MyReceiver.conf`, `ogn-rf.fifo`, and `WW15MGH.DAC`.

## SD Card Protection (Overlay Filesystem)

The `overlayroot` package provides a read-only root filesystem with a RAM-based overlay. All writes go to RAM and are discarded on reboot — the SD card is never written to, preventing corruption from power loss and reducing wear.

```bash
# Check current status
/home/pi/scripts/overlay-ctl.sh status

# Enable read-only mode (reboot required)
/home/pi/scripts/overlay-ctl.sh enable
sudo reboot

# To make persistent changes (e.g. config edits), disable overlay first
/home/pi/scripts/overlay-ctl.sh disable
sudo reboot
# ... make changes ...
/home/pi/scripts/overlay-ctl.sh enable
sudo reboot
```

When overlay is active, the real (read-only) root is mounted at `/media/root-ro`. The auto-update script handles the overlay automatically — it writes to the real root and reboots to apply changes.

**Important**: Do NOT enable the overlay until initial setup at the club is complete (dongle calibration, config, WiFi).

## WiFi Configuration

WiFi is managed via NetworkManager/netplan. The Pi auto-connects to known networks.

- Add a network: `/home/pi/scripts/add-club-wifi.sh "SSID" "password"`
- List known networks: `nmcli connection show`
- Scan for networks: `nmcli device wifi list`
- Remove a network: `nmcli connection delete "connection-name"`
- Netplan configs: `/etc/netplan/90-NM-*.yaml`

The regulatory domain is set to NL (Netherlands) in `/boot/firmware/cmdline.txt` via `cfg80211.ieee80211_regdom=NL`.

## Troubleshooting

- **"no dongle found"**: Check `lsusb` for RTL2832U device. Ensure blacklist is active (reboot after creating it). Check `/etc/modprobe.d/rtl-glidernet-blacklist.conf`.
- **Service won't start**: It waits for NTP sync. Check `ntpq -p` for sync status. On a fresh boot without network, this blocks.
- **Poor reception**: Re-run `gsm_scan` to verify FreqCorr. Adjust OGN Gain (try 40-50 dB). Ensure antenna is connected.
