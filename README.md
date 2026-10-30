# 🤖 Pepa Hacks — Roborock S5 Speed + Radio

**Unlock your Roborock S5's full potential.** This project adds:

- ⚡ **6 speed presets** — from Slow (0.20 m/s) to Max (0.80 m/s), up to +167% faster than factory
- 📻 **Internet radio** — 13 pre-loaded stations (Czech, Greek, US), add your own via the UI
- 🔊 **Volume control** — slider in the Valetudo web UI
- 🗺️ **SLAM-accurate** — faster speeds don't break the map

Everything runs **100% locally** — no cloud, no Roborock app, no data leaving your network.

---

## ⚠️ Prerequisites

| Requirement | Details |
|-------------|---------|
| **Robot** | Roborock S5 (tested), may work on S5 Max / S6 |
| **Firmware** | [Dustfab Valetudo](https://fab.valetudo.cloud) — you need the SSH key from your build email |
| **SSH key** | The ed25519 key pair from Dustfab (usually `dustfab-XXXKeyYYY.key`) |
| **Network** | Robot and your computer on the same LAN |

> ⚠️ **This modifies system files on your robot.** A backup is created automatically. Read the revert instructions before proceeding.

---

## 🚀 Quick Install

SSH into your robot and run:

```bash
# From the robot shell:
wget -qO- https://raw.githubusercontent.com/yourusername/pepa-hacks/main/scripts/install.sh | sh
```

Or manually:

```bash
# 1. SSH into robot
ssh -i ~/path/to/your-dustfab-key.key root@YOUR-ROBOT-IP

# 2. Run installer
wget -qO /tmp/install.sh https://raw.githubusercontent.com/yourusername/pepa-hacks/main/scripts/install.sh
sh /tmp/install.sh
```

---

## 📋 What Gets Installed

| File | Location | Purpose |
|------|----------|---------|
| `speed_override.so` | `/mnt/data/` | LD_PRELOAD library — overrides navigation planning speeds |
| `mpg123_bin` | `/mnt/data/` | MP3 decoder (static ARM binary) |
| `alsa_play` | `/mnt/data/` | Writes audio to robot speaker |
| `mpg123` | `/mnt/data/` | Volume wrapper script |
| `speed.conf` | `/mnt/data/` | Current speed setting |
| `radio_volume.conf` | `/mnt/data/` | Current volume (0–100) |
| `/etc/ld.so.preload` | system | Loads speed_override.so on every process start |

**Backup created automatically:** `/mnt/data/librrnavdrv.so.orig`

---

## 🎛️ Using Speed Control

### Via the web UI (requires patched Valetudo)

Open `http://YOUR-ROBOT-IP` — the Speed slider is below the Fan control.

### Via the API

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

| Preset | Speed | vs Factory | Best for |
|--------|-------|-----------|----------|
| `slow` | 0.20 m/s | −33% | Carpet, delicate areas |
| `normal` | 0.30 m/s | = factory | Default behavior |
| `fast` | 0.45 m/s | +50% | Daily cleaning ⭐ |
| `turbo` | 0.55 m/s | +83% | Large open rooms |
| `ultra` | 0.65 m/s | +117% | Quick pass |
| `max` | 0.80 m/s | +167% | Speed test only |

> **Tip:** Speed changes take effect immediately — the robot briefly pauses (~1.5s) then resumes at the new speed. SLAM stays accurate because both planning and execution happen at the same speed.

---

## 📻 Using Radio

### Via the web UI (requires patched Valetudo)

Open `http://YOUR-ROBOT-IP` — the Radio card is below the Speed control.

### Via the API

```bash
ROBOT=http://YOUR-ROBOT-IP

# List available stations
curl $ROBOT/api/v2/robot/radio

# Play a station
curl -X PUT $ROBOT/api/v2/robot/radio \
  -H 'Content-Type: application/json' \
  -d '{"station": "evropa2"}'

# Stop
curl -X DELETE $ROBOT/api/v2/robot/radio

# Set volume (0-100)
curl -X PUT $ROBOT/api/v2/robot/radio/volume \
  -H 'Content-Type: application/json' \
  -d '{"value": 60}'

# Add custom station
curl -X POST $ROBOT/api/v2/robot/radio/stations \
  -H 'Content-Type: application/json' \
  -d '{"id":"mystation","name":"My Radio","country":"CZ","url":"http://stream.example.com/radio.mp3"}'
```

### Pre-loaded stations

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

> **Adding stations:** Any direct MP3 stream URL works. Test with: `wget -O - YOUR_URL | wc -c` — if it downloads bytes, it works. AAC streams (`.aac`, `.m4a`) are not supported.

---

## 🏗️ Patched Valetudo (for full UI)

The speed and radio APIs work immediately after install. For the **web UI controls** (sliders in the browser), you need the patched Valetudo binary.

**Download from [Releases](https://github.com/yourusername/pepa-hacks/releases)** and install:

```bash
# On your robot:
wget -O /mnt/data/valetudo-new https://github.com/yourusername/pepa-hacks/releases/download/latest/valetudo-armv7
chmod +x /mnt/data/valetudo-new
cp /mnt/data/valetudo-new /usr/local/bin/valetudo
reboot
```

---

## ↩️ Reverting Everything

```bash
# SSH into robot
ssh -i your-key.key root@YOUR-ROBOT-IP

# 1. Restore original navigation library
cp /mnt/data/librrnavdrv.so.orig /opt/rockrobo/cleaner/lib/librrnavdrv.so

# 2. Remove LD_PRELOAD speed hook
rm /etc/ld.so.preload

# 3. Restore original Valetudo (if you replaced it)
# cp /mnt/data/valetudo-dustfab.bak /usr/local/bin/valetudo

# 4. Reboot
reboot
```

---

## 🔧 Troubleshooting

**Speed change not working?**
- Make sure `speed.conf` exists: `cat /mnt/data/speed.conf`
- Check LD_PRELOAD is set: `cat /etc/ld.so.preload`
- Verify .so is loaded: `grep -c speed_override /proc/$(pgrep rr_loader)/maps`
- Restart rr_loader: `kill -9 $(pgrep rr_loader)` (WatchDoge restarts it)

**Radio exits immediately?**
- Test stream URL: `wget -O - YOUR_URL | /mnt/data/mpg123_bin -s - | wc -c`
- Result > 1000 bytes = stream works. AAC streams are not supported.
- Check volume: `cat /mnt/data/radio_volume.conf` (should be 10-100)

**Map looks wrong after speed change?**
- This was fixed in `speed_override.so` v4 — the nav plans AND executes at the same speed
- If you're on an old version: download the latest `speed_override.so` from releases

**Robot crashes / behaves strangely?**
- Revert using the commands above — the backup is always at `/mnt/data/librrnavdrv.so.orig`

---

## 🏗️ Building from Source

See [`source/`](source/) for the C source files. Build on Ubuntu 16.04 (required for glibc 2.19 compatibility with the robot's libc):

```bash
# Requires docker/podman with Ubuntu 16.04
docker run --rm -v $(pwd):/src ubuntu:16.04 bash -c '
  apt-get install -y gcc-arm-linux-gnueabihf
  arm-linux-gnueabihf-gcc -shared -fPIC -march=armv7-a -mfpu=vfpv3-d16 \
    -mfloat-abi=hard -O2 -ldl /src/source/speed_override_v4.c \
    -o /src/binaries/speed_override.so
'
```

---

## 📖 How It Works

### Speed Hack

The navigation library (`librrnavdrv.so`) has hardcoded speed limits as float constants at specific offsets in the binary. We:

1. **Disk patch** the float constants (8 bytes changed, `/opt` is writable)
2. **LD_PRELOAD** inject `speed_override.so` via `/etc/ld.so.preload` — this library overrides the `NavConfig::WallFollower::Get_SPEED()` and related functions to read from `/mnt/data/speed.conf` on every call
3. **Pause+Resume** via miio IPC forces the nav to re-read the new speed during a cleaning session

The key insight: we override the **planning** speed functions (not the motion commands), so the navigation algorithm plans sweep rows at the correct speed. Both planning and execution happen at the same speed → SLAM stays accurate, map doesn't drift.

### Radio

Pipeline: `wget (HTTPS stream) | mpg123_bin -s - (decode MP3) | alsa_play (ALSA output)`

The robot has an ALSA audio device (`audiocodec`, `plughw:0,0`). We use a static mpg123 binary as the MP3 decoder, piping PCM data to a tiny custom ALSA writer binary.

---

## ⚖️ License & Disclaimer

MIT License. Use at your own risk. This modifies firmware on a physical device — always keep the backup and know how to revert. This project is not affiliated with Roborock, Valetudo, or Dustfab.

---

## 🙏 Credits

- [Valetudo](https://valetudo.cloud) — the open-source robot vacuum firmware layer
- [Dustfab](https://fab.valetudo.cloud) — Valetudo builds with SSH access
- [Radio Browser](https://www.radio-browser.info) — community radio stream database
