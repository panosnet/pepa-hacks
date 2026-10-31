#!/bin/sh
# Pepa Hacks — Automated installer for Roborock S5 with Dustfab Valetudo
# https://github.com/panosnet/pepa-hacks
#
# Run this script ON THE ROBOT (not on your computer):
#   wget -O /tmp/install.sh https://raw.githubusercontent.com/panosnet/pepa-hacks/main/scripts/install.sh
#   sh /tmp/install.sh
#
# NOTE: Never pipe install scripts directly to sh (wget -O- ... | sh) — always
# download, inspect, then run.

set -e

REPO_URL="https://raw.githubusercontent.com/panosnet/pepa-hacks/main"
INSTALL_DIR="/mnt/data"
LIB="/opt/rockrobo/cleaner/lib/librrnavdrv.so"
STAGING_DIR="/tmp/pepa_hacks_staging"

# SHA256 checksums of shipped binaries — verification before install
SHA256_SPEED_OVERRIDE="76ca02ea274f4489ae1594682edbb2adbbc02f5279641a02930cd79d8ab5724e"
SHA256_ALSA_PLAY="40872463fc75f96134f5946bee4272c0fd99f4d9e0e5ec64e9a1429a4decde22"
SHA256_MPG123_BIN="d908cb1c382bc741161e4fc79b2a7208b0f331995ef2c75e4c038755554e7b2b"

# Expected bytes in librrnavdrv.so BEFORE patching (safety check)
# If these don't match, we're patching the wrong library version
EXPECTED_BEFORE_HEX_MAX="9a9999 3e"   # float 0.30 at offset 0x308e28
EXPECTED_BEFORE_HEX_LIM="3333b3 3e"   # float 0.35 at offset 0x308e34

# Rollback: restore library and ld.so.preload entry if we fail after patching
_PATCHED=0
rollback() {
    if [ "$_PATCHED" = "1" ]; then
        echo ""
        echo "!!! Installation failed — rolling back library patch !!!"
        if [ -f "$INSTALL_DIR/librrnavdrv.so.orig" ]; then
            cp "$INSTALL_DIR/librrnavdrv.so.orig" "$LIB" && echo "  Library restored."
        fi
        if grep -q "speed_override.so" /etc/ld.so.preload 2>/dev/null; then
            grep -v "speed_override.so" /etc/ld.so.preload > /tmp/preload_tmp \
                && mv /tmp/preload_tmp /etc/ld.so.preload
            echo "  Removed from /etc/ld.so.preload."
        fi
        rm -f "$INSTALL_DIR/speed_override.so"
    fi
    rm -rf "$STAGING_DIR"
}
trap rollback EXIT

echo ""
echo "=========================================="
echo "  Pepa Hacks — Roborock S5 Speed + Radio"
echo "=========================================="
echo ""

# Verify we're on the robot
if [ ! -f "$LIB" ]; then
    echo "ERROR: Run this script ON THE ROBOT, not on your computer."
    echo "SSH into the robot first, then run this script."
    exit 1
fi

# Verify sha256sum is available
if ! command -v sha256sum > /dev/null 2>&1; then
    echo "ERROR: sha256sum not found. Cannot verify binary integrity."
    exit 1
fi

verify_sha256() {
    local file="$1" expected="$2" name="$3"
    actual=$(sha256sum "$file" | awk '{print $1}')
    if [ "$actual" != "$expected" ]; then
        echo "ERROR: SHA256 mismatch for $name!"
        echo "  Expected: $expected"
        echo "  Got:      $actual"
        echo "Aborting for your safety. Do not use this file."
        rm -f "$file"
        exit 1
    fi
    echo "  SHA256 verified: $name ✓"
}

download_and_verify() {
    local url="$1" dest="$2" expected_sha256="$3" name="$4"
    echo "  Downloading $name..."
    wget -q -O "$dest" "$url"
    verify_sha256 "$dest" "$expected_sha256" "$name"
}

echo "[0/6] Pre-downloading and verifying all binaries (before any system change)..."
mkdir -p "$STAGING_DIR"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

for item in "speed_override.so:$SHA256_SPEED_OVERRIDE" "mpg123_bin:$SHA256_MPG123_BIN" "alsa_play:$SHA256_ALSA_PLAY"; do
    binary="${item%%:*}"; sha="${item##*:}"
    LOCAL_BIN="$SCRIPT_DIR/../binaries/$binary"
    if [ -f "$LOCAL_BIN" ]; then
        cp "$LOCAL_BIN" "$STAGING_DIR/$binary"
    else
        echo "  Downloading $binary..."
        wget -q -O "$STAGING_DIR/$binary" "$REPO_URL/binaries/$binary"
    fi
    verify_sha256 "$STAGING_DIR/$binary" "$sha" "$binary"
done
echo "  All binaries verified — proceeding with install."
echo ""

echo "[1/6] Backing up original navigation library..."
if [ ! -f "$INSTALL_DIR/librrnavdrv.so.orig" ]; then
    cp "$LIB" "$INSTALL_DIR/librrnavdrv.so.orig"
    echo "  Backup saved to $INSTALL_DIR/librrnavdrv.so.orig"
else
    echo "  Backup already exists at $INSTALL_DIR/librrnavdrv.so.orig"
fi

echo ""
echo "[2/6] Verifying navigation library version before patching..."
# Read current bytes at the patch offsets to confirm we're patching the right version
# Read current bytes at patch offsets using od for reliable hex output
actual_max=$(dd if="$LIB" bs=1 skip=3182120 count=4 2>/dev/null | od -An -tx1 | tr -d " \n")
actual_lim=$(dd if="$LIB" bs=1 skip=3182132 count=4 2>/dev/null | od -An -tx1 | tr -d " \n")

if [ "$actual_max" = "9a99993e" ] && [ "$actual_lim" = "3333b33e" ]; then
    # Unpatched factory library — safe to patch
    echo "  Patching MAX_SPEED: 0.30 m/s → 0.50 m/s"
    printf "\000\000\000\077" | dd of="$LIB" bs=1 seek=3182120 conv=notrunc 2>/dev/null
    printf "\000\000\000\077" | dd of="$LIB" bs=1 seek=3182132 conv=notrunc 2>/dev/null
    # Verify the write landed
    verify=$(dd if="$LIB" bs=1 skip=3182120 count=4 2>/dev/null | od -An -tx1 | tr -d " \n")
    if [ "$verify" != "0000003f" ]; then
        echo "ERROR: Patch verification failed — restoring backup"
        cp "$INSTALL_DIR/librrnavdrv.so.orig" "$LIB"
        exit 1
    fi
    _PATCHED=1  # arm rollback — library is now modified
    echo "  Patch verified ✓"
elif [ "$actual_max" = "0000003f" ]; then
    echo "  Library already patched, skipping."
else
    echo "ERROR: Unexpected bytes at patch offsets (max=$actual_max lim=$actual_lim)"
    echo "  This may be a different librrnavdrv.so version. Aborting to be safe."
    echo "  Your robot is unchanged — no harm done."
    exit 1
fi

echo ""
echo "[3/6] Installing speed_override.so (live speed changes)..."
# Use pre-verified staging copy (already checksummed in step 0)
cp "$STAGING_DIR/speed_override.so" "$INSTALL_DIR/speed_override.so"
chmod +x "$INSTALL_DIR/speed_override.so"
echo "  speed_override.so installed (pre-verified)"

# Add to ld.so.preload (append-safe: only add if not already present)
if ! grep -q "speed_override.so" /etc/ld.so.preload 2>/dev/null; then
    echo "/mnt/data/speed_override.so" >> /etc/ld.so.preload
    echo "  Added to /etc/ld.so.preload"
else
    echo "  Already in /etc/ld.so.preload"
fi
echo "fast" > "$INSTALL_DIR/speed.conf"
echo "  Default speed: fast (0.45 m/s)"

echo ""
echo "[4/6] Installing radio binaries..."
# Use pre-verified staging copies (already checksummed in step 0)
for binary in mpg123_bin alsa_play; do
    cp "$STAGING_DIR/$binary" "$INSTALL_DIR/$binary"
    chmod +x "$INSTALL_DIR/$binary"
    echo "  $binary installed (pre-verified)"
done

cat > "$INSTALL_DIR/mpg123" << 'MPGEOF'
#!/bin/sh
VOL=$(tr -cd '0-9' < /mnt/data/radio_volume.conf 2>/dev/null | head -c 3)
VOL=$(printf '%s' "$VOL" | sed 's/^0*//')
case "$VOL" in ''|*[!0-9]*) VOL=50 ;; esac
[ "$VOL" -gt 100 ] 2>/dev/null && VOL=100
SCALE=$(( VOL * 328 ))
[ "$SCALE" -gt 32768 ] && SCALE=32768
exec /mnt/data/mpg123_bin --scale "$SCALE" "$@"
MPGEOF
chmod +x "$INSTALL_DIR/mpg123"
echo "50" > "$INSTALL_DIR/radio_volume.conf"
echo "  Radio binaries installed (volume default: 50%)"

echo ""
echo "[5/6] Creating station config..."
if [ ! -f "$INSTALL_DIR/radio_stations.json" ]; then
    echo '{}' > "$INSTALL_DIR/radio_stations.json"
fi
echo "  Custom stations file ready (add via Valetudo UI)"

echo ""
echo "[5b/6] Cleaning up staging area..."
rm -rf "$STAGING_DIR"
_PATCHED=0  # disarm rollback — install succeeded
trap - EXIT

echo "[6/6] Applying changes (restart rr_loader)..."
RR_PID=$(ps -w | grep 'rr_loader -d' | grep -v grep | awk '{print $1}' | head -1)
if [ -n "$RR_PID" ]; then
    kill -9 "$RR_PID" 2>/dev/null || true
    echo "  rr_loader restarted (WatchDoge brings it back in ~2s)"
else
    echo "  rr_loader not running — changes apply on next reboot"
fi

echo ""
echo "=========================================="
echo "  Installation complete!"
echo ""
echo "  Speed: 0.30 → 0.45 m/s (fast preset)"
echo "  Presets: slow(0.20) normal(0.30) fast(0.45)"
echo "           turbo(0.55) ultra(0.65) max(0.80) m/s"
echo ""
echo "  Speed API:"
echo "    curl -X PUT http://ROBOT-IP/api/v2/robot/cleaning_speed \\"
echo "         -H 'Content-Type: application/json' \\"
echo "         -d '{\"speed\":\"turbo\"}'"
echo ""
echo "  Radio API:"
echo "    curl -X PUT http://ROBOT-IP/api/v2/robot/radio \\"
echo "         -H 'Content-Type: application/json' \\"
echo "         -d '{\"station\":\"evropa2\"}'"
echo ""
echo "  To REVERT:"
echo "    cp $INSTALL_DIR/librrnavdrv.so.orig $LIB"
echo "    grep -v speed_override /etc/ld.so.preload > /tmp/p && mv /tmp/p /etc/ld.so.preload"
echo "    reboot"
echo "=========================================="
