# 🤖 Pepa Hacks — Roborock S5 Speed + Radio

**Unlock your Roborock S5's full potential.** This project adds:

- ⚡ **6 speed presets** — from Slow (0.20 m/s) to Max (0.80 m/s), up to +167% faster than factory
- 📻 **Internet radio** — 13 pre-loaded stations (Czech, Greek, US), add your own via the UI
- 🔊 **Volume control** — slider in the Valetudo web UI
- 🗺️ **SLAM-accurate** — faster speeds don't break the map

Everything runs **100% locally** — no cloud, no Roborock app, no data leaving your network.

---

## 📋 Which situation are you in?

| Situation | Go to |
|-----------|-------|
| I don't have Valetudo yet | [→ Step 0: Install Valetudo](#step-0-install-valetudo-first) |
| I have Valetudo but **no SSH key** | [→ Valetudo without SSH](#valetudo-without-ssh) |
| I have Valetudo + SSH (any build) | [→ Quick Install](#quick-install) |
| I want the full web UI (sliders) | [→ Patched Valetudo](#patched-valetudo-web-ui) |

---

## Step 0: Install Valetudo First

> Skip this if you already have Valetudo running.

**Valetudo** is open-source firmware for Roborock vacuums that replaces the cloud app with a local web UI. You need it installed before applying these hacks.

### Option A — Dustfab Build (Recommended — includes SSH by default)

[Dustfab](https://fab.valetudo.cloud) provides pre-built Valetudo firmware for Roborock robots with SSH already configured.

1. Go to **https://fab.valetudo.cloud**
2. Select your robot model: **Roborock S5**
3. Build the firmware — you'll receive an email with:
   - A `.pkg` firmware file
   - Your SSH private key (`dustfab-XXXKeyPeppa.key`)
4. Put your robot in **AP mode** (hold button 5s → blinking WiFi light)
5. Connect your computer to the robot's WiFi hotspot
6. Flash the firmware using the Dustfab web interface
7. Configure your home WiFi in the Valetudo setup page
8. Your robot will reboot and appear on your LAN

After setup, test SSH works:
```bash
ssh -i ~/path/to/your-dustfab-key.key root@YOUR-ROBOT-IP
# Should show: root@rockrobo:~#
```

### Option B — Official Valetudo (requires UART for initial flash)

Follow the [official Valetudo installation guide](https://valetudo.cloud/pages/general/getting-started.html). This requires a USB-UART adapter and opening the robot.

---

## Valetudo without SSH

If you have Valetudo but **no SSH access** (e.g. official build without SSH configured):

**Option 1:** Use Valetudo's web UI to trigger a factory reset, then reflash with Dustfab (which gives you SSH). Your map will be lost but everything else is reversible.

**Option 2:** Use the Valetudo REST API directly — the speed and radio features work entirely through HTTP API calls, no SSH needed for *using* them. But you need SSH for the *install* step.

For the initial install, SSH is required. After that, everything is controlled via the web UI or API.

---

## Quick Install

**You need:** Valetudo running + SSH access to your robot.

```bash
# 1. SSH into your robot
ssh -i ~/path/to/your-dustfab-key.key root@YOUR-ROBOT-IP

# 2. Download the installer (always inspect before running)
wget -O /tmp/install.sh \
  https://raw.githubusercontent.com/panosnet/pepa-hacks/main/scripts/install.sh

# 3. Review it
cat /tmp/install.sh

# 4. Run it
sh /tmp/install.sh
```

The installer:
- Backs up your original navigation library
- Patches the speed limit (0.30 → 0.45 m/s)
- Installs the LD_PRELOAD library for live speed changes
- Installs radio binaries (mpg123, alsa_play)
- Verifies all binaries with SHA256 checksums before installing

---

## Patched Valetudo (web UI)

The speed and radio APIs work immediately after install. For **sliders in the browser** (Speed card, Radio card with volume), you need the patched Valetudo binary.

### Install patched Valetudo

```bash
# SSH into robot
ssh -i ~/path/to/your-dustfab-key.key root@YOUR-ROBOT-IP

# Download patched Valetudo from releases
wget -O /mnt/data/valetudo-new \
  https://github.com/panosnet/pepa-hacks/releases/download/latest/valetudo-armv7

# Verify checksum (find hash in the release notes)
sha256sum /mnt/data/valetudo-new

# Back up current Valetudo
cp /usr/local/bin/valetudo /mnt/data/valetudo-original.bak

# Install and reboot
chmod +x /mnt/data/valetudo-new
cp /mnt/data/valetudo-new /usr/local/bin/valetudo
sync && reboot
```

After reboot, open `http://YOUR-ROBOT-IP` — you'll see:

```
Controls panel (left side):
  🌀 Fan          Max ▾
  ⚡ Speed        Fast ▾   ← drag slider or pick preset
  📻 Radio    Evropa 2  ▶   ← station dropdown + volume slider
```

### Revert to original Valetudo

```bash
cp /mnt/data/valetudo-original.bak /usr/local/bin/valetudo
reboot
```

---

## 📋 What Gets Installed

| File | Location | Purpose |
|------|----------|---------|
| `speed_override.so` | `/mnt/data/` | LD_PRELOAD library — overrides navigation planning speeds |
| `mpg123_bin` | `/mnt/data/` | MP3 decoder (static ARM binary, no dependencies) |
| `alsa_play` | `/mnt/data/` | Writes decoded audio to robot speaker |
| `mpg123` | `/mnt/data/` | Volume wrapper (reads `radio_volume.conf`) |
| `speed.conf` | `/mnt/data/` | Current speed preset |
| `radio_volume.conf` | `/mnt/data/` | Current volume 0–100 |
| `/etc/ld.so.preload` | system | Loads speed_override.so on rr_loader start |

**Backup:** `/mnt/data/librrnavdrv.so.orig` — original navigation library

---

## 🎛️ Speed Control

### Via web UI
Open `http://YOUR-ROBOT-IP` → Speed slider below Fan.

### Via API

```bash
ROBOT=http://YOUR-ROBOT-IP

# Set speed preset
curl -X PUT $ROBOT/api/v2/robot/cleaning_speed \
  -H 'Content-Type: application/json' \
  -d '{"speed": "turbo"}'

# Get current speed
curl $ROBOT/api/v2/robot/cleaning_speed
```

### Speed presets

| Preset | Speed | vs Factory | Notes |
|--------|-------|-----------|-------|
| `slow` | 0.20 m/s | −33% | Carpets, delicate areas |
| `normal` | 0.30 m/s | = factory | Original speed |
| `fast` | 0.45 m/s | +50% | Recommended daily ⭐ |
| `turbo` | 0.55 m/s | +83% | Large open rooms |
| `ultra` | 0.65 m/s | +117% | Quick clean |
| `max` | 0.80 m/s | +167% | Maximum tested |

> **Speed changes during cleaning:** The robot briefly pauses (~1.5 seconds) then resumes at the new speed. Map accuracy is preserved because the navigation plans AND executes at the same speed.

---

## 📻 Radio

### Via web UI
Open `http://YOUR-ROBOT-IP` → Radio card below Speed. Drag the volume slider.

### Via API

```bash
ROBOT=http://YOUR-ROBOT-IP

# List stations
curl $ROBOT/api/v2/robot/radio

# Play a station
curl -X PUT $ROBOT/api/v2/robot/radio \
  -H 'Content-Type: application/json' \
  -d '{"station": "evropa2"}'

# Stop
curl -X DELETE $ROBOT/api/v2/robot/radio

# Volume (0–100)
curl -X PUT $ROBOT/api/v2/robot/radio/volume \
  -H 'Content-Type: application/json' \
  -d '{"value": 60}'

# Add custom station
curl -X POST $ROBOT/api/v2/robot/radio/stations \
  -H 'Content-Type: application/json' \
  -d '{"id":"mystation","name":"My Radio","country":"CZ","url":"http://stream.example.com/radio.mp3"}'
```

### Pre-loaded stations (all verified working)

| ID | Station | Country |
|----|---------|---------|
| `evropa2` | Evropa 2 | 🇨🇿 |
| `frekvence1` | Frekvence 1 | 🇨🇿 |
| `beat` | Radio Beat | 🇨🇿 |
| `cro1` | ČRo Radiožurnál | 🇨🇿 |
| `country` | Country Radio | 🇨🇿 |
| `rockzone` | Rockzone | 🇨🇿 |
| `kissdelta` | Kiss Delta | 🇨🇿 |
| `offradio` | OffRadio | 🇬🇷 |
| `pepper` | Pepper 96.6 | 🇬🇷 |
| `rythmos` | Rythmos 94.9 | 🇬🇷 |
| `groovesalad` | Groove Salad | 🇺🇸 |
| `secretagent` | Secret Agent | 🇺🇸 |
| `dronezone` | Drone Zone | 🇺🇸 |

> **Adding stations:** Any MP3 HTTP stream works. Test from the robot: `wget -O - URL | wc -c` — if bytes download, it works. AAC streams are not supported (mpg123 limitation).

---

## ↩️ Revert Everything

```bash
ssh -i ~/path/to/your-key.key root@YOUR-ROBOT-IP

# 1. Restore original navigation library
cp /mnt/data/librrnavdrv.so.orig /opt/rockrobo/cleaner/lib/librrnavdrv.so

# 2. Remove LD_PRELOAD hook (leaves other preloads intact)
grep -v speed_override /etc/ld.so.preload > /tmp/p && mv /tmp/p /etc/ld.so.preload

# 3. Restore original Valetudo (if you replaced it)
# cp /mnt/data/valetudo-original.bak /usr/local/bin/valetudo

# 4. Reboot
reboot
```

---

## 🔧 Troubleshooting

**Speed change not working?**
```bash
# Check LD_PRELOAD is set
cat /etc/ld.so.preload

# Check .so is loaded in rr_loader
grep -c speed_override /proc/$(pgrep rr_loader)/maps

# Check speed.conf
cat /mnt/data/speed.conf

# Restart rr_loader (WatchDoge auto-restarts in ~2s)
kill -9 $(pgrep rr_loader)
```

**Radio exits immediately?**
```bash
# Test stream from robot
wget -O - 'http://STREAM-URL' | /mnt/data/mpg123_bin -s - | wc -c
# Result > 1000 bytes = works. 0 = URL is broken or geo-blocked.
```

**Map looks wrong after speed change?**
- The `speed_override.so` v4 included here uses the correct approach — it overrides planning speeds, not motion commands, so SLAM stays accurate.
- If you compiled your own older version: download the latest from releases.

**Valetudo UI shows 404 / no controls?**
- You need the patched Valetudo binary — see [Patched Valetudo](#patched-valetudo-web-ui)
- Hard-refresh the browser: `Cmd+Shift+R` (Mac) or `Ctrl+Shift+R` (Windows/Linux)

---

## 🏗️ Building from Source

See [`source/`](source/) for C source files with comments. Requires Ubuntu 16.04 cross-compiler (glibc 2.19 compatibility):

```bash
docker run --rm -v $(pwd):/src ubuntu:16.04 bash -c '
  apt-get update -qq && apt-get install -y gcc-arm-linux-gnueabihf -qq
  arm-linux-gnueabihf-gcc -shared -fPIC -march=armv7-a -mfpu=vfpv3-d16 \
    -mfloat-abi=hard -O2 -ldl \
    /src/source/speed_override_v4.c -o /src/binaries/speed_override.so
  echo "SHA256: $(sha256sum /src/binaries/speed_override.so)"
'
```

---

## 📖 Technical Details

Full writeup with ARM Thumb2 disassembly, LD_PRELOAD internals, audio pipeline, and everything that went wrong (and why): [`pepa_final_writeup.html`](pepa_final_writeup.html)

Short version:

- **Speed:** The navigation library (`librrnavdrv.so`) has hardcoded float constants. We patch 8 bytes on disk, then inject `speed_override.so` via `/etc/ld.so.preload` to intercept `NavConfig::WallFollower::Get_SPEED()` and friends. Both planning and execution use the same speed — SLAM stays accurate.
- **Radio:** `wget` downloads the HTTPS stream → `mpg123_bin -s -` decodes MP3 to raw PCM → `alsa_play` writes to the robot's ALSA device (`plughw:0,0`). Volume is controlled via mpg123's `--scale` flag.

---

## ⚖️ Disclaimer

This project modifies firmware on a physical device. Use at your own risk. Always keep the backup (`/mnt/data/librrnavdrv.so.orig`) and know how to revert.

Not affiliated with Roborock, Valetudo, or Dustfab.

---

## 🙏 Credits

- [Valetudo](https://valetudo.cloud) — open-source robot vacuum firmware
- [Dustfab](https://fab.valetudo.cloud) — Valetudo builds with SSH
- [Radio Browser](https://www.radio-browser.info) — community radio stream database
