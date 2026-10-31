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
STAGING_DIR=""  # set after robot check, via mktemp

# SHA256 checksums of shipped binaries — verification before install
SHA256_SPEED_OVERRIDE="76ca02ea274f4489ae1594682edbb2adbbc02f5279641a02930cd79d8ab5724e"
SHA256_ALSA_PLAY="40872463fc75f96134f5946bee4272c0fd99f4d9e0e5ec64e9a1429a4decde22"
SHA256_MPG123_BIN="d908cb1c382bc741161e4fc79b2a7208b0f331995ef2c75e4c038755554e7b2b"

# Expected bytes in librrnavdrv.so BEFORE patching (safety check)
# If these don't match, we're patching the wrong library version
EXPECTED_BEFORE_HEX_MAX="9a9999 3e"   # float 0.30 at offset 0x308e28
EXPECTED_BEFORE_HEX_LIM="3333b3 3e"   # float 0.35 at offset 0x308e34

# Two rollback flags — tracked independently:
#   _PATCHED=1   : librrnavdrv.so has been modified (needs library restore)
#   _PRELOADED=1 : /etc/ld.so.preload entry has been added (needs removal)
_PATCHED=0
_PRELOADED=0

rollback() {
    local _rc=0
    echo ""

    # Step 1: remove preload entry FIRST, then remove the .so.
    # Fail-closed: if we cannot safely rewrite ld.so.preload, leave .so in
    # place so the entry does not dangle. Print a manual-action message.
    if [ "$_PRELOADED" = "1" ] && \
       grep -q 'speed_override\.so' /etc/ld.so.preload 2>/dev/null; then
        echo "!!! Rolling back /etc/ld.so.preload entry !!!"
        _tmpf="$(mktemp /etc/.ld.so.preload.XXXXXX 2>/dev/null)" || {
            echo "FATAL: cannot create temp file in /etc." >&2
            echo "  /etc/ld.so.preload still references /mnt/data/speed_override.so." >&2
            echo "  Remove that line manually BEFORE rebooting to avoid a boot failure." >&2
            _rc=1
        }
        if [ -n "$_tmpf" ]; then
            if grep -v 'speed_override\.so' /etc/ld.so.preload > "$_tmpf" \
               && chmod 644 "$_tmpf" && mv "$_tmpf" /etc/ld.so.preload; then
                echo "  Removed from /etc/ld.so.preload."
                rm -f "$INSTALL_DIR/speed_override.so"
            else
                rm -f "$_tmpf"
                echo "FATAL: failed to rewrite /etc/ld.so.preload." >&2
                echo "  Leaving speed_override.so in place to avoid a dangling preload entry." >&2
                echo "  Fix manually BEFORE rebooting." >&2
                _rc=1
            fi
        fi
    fi

    # Step 2: restore the navigation library if we patched it.
    if [ "$_PATCHED" = "1" ]; then
        echo "!!! Rolling back library patch !!!"
        if [ -f "$INSTALL_DIR/librrnavdrv.so.orig" ]; then
            cp "$INSTALL_DIR/librrnavdrv.so.orig" "$LIB" && echo "  Library restored."
        else
            echo "WARNING: backup not found at $INSTALL_DIR/librrnavdrv.so.orig" >&2
        fi
    fi

    rm -rf "$STAGING_DIR"
    return "$_rc"
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

# Create private staging dir — unpredictable name, root-only (mode 0700)
STAGING_DIR="$(mktemp -d /tmp/pepa_hacks.XXXXXX)" || { echo "ERROR: mktemp failed"; exit 1; }
chmod 700 "$STAGING_DIR"

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

# Post-install sanity check (belt-and-suspenders for filesystem corruption).
# Removes the file on mismatch ONLY when ld.so.preload does not yet reference
# it — if it does, the rollback trap owns removal (preload entry first, then
# the file) to prevent a dangling preload on reboot.
verify_installed_sha256() {
    local file="$1" expected="$2" name="$3"
    actual=$(sha256sum "$file" | awk '{print $1}')
    if [ "$actual" != "$expected" ]; then
        echo "ERROR: Post-install SHA256 mismatch for $name!" >&2
        echo "  Expected: $expected" >&2
        echo "  Got:      $actual" >&2
        if ! grep -q 'speed_override\.so' /etc/ld.so.preload 2>/dev/null; then
            rm -f "$file"
        fi
        exit 1
    fi
    echo "  Post-install SHA256 verified: $name ✓"
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
# Pre-arm _PRELOADED if the preload entry already exists (reinstall path).
# This ensures rollback removes the entry before the file on any failure,
# preventing a dangling preload → boot failure.
if grep -q 'speed_override\.so' /etc/ld.so.preload 2>/dev/null; then
    _PRELOADED=1
fi
# mv (atomic) from already-SHA256-verified staging.
# verify_installed_sha256 only rm -f when _PRELOADED=0 (no preload reference yet).
mv "$STAGING_DIR/speed_override.so" "$INSTALL_DIR/speed_override.so"
verify_installed_sha256 "$INSTALL_DIR/speed_override.so" "$SHA256_SPEED_OVERRIDE" "speed_override.so"
chmod 755 "$INSTALL_DIR/speed_override.so"
echo "  speed_override.so installed and verified"

# Add to ld.so.preload if not already present, then arm rollback.
if ! grep -q "speed_override.so" /etc/ld.so.preload 2>/dev/null; then
    echo "/mnt/data/speed_override.so" >> /etc/ld.so.preload
    echo "  Added to /etc/ld.so.preload"
else
    echo "  Already in /etc/ld.so.preload"
fi
_PRELOADED=1  # arm/confirm — preload entry and verified .so are both in place
echo "fast" > "$INSTALL_DIR/speed.conf"
echo "  Default speed: fast (0.45 m/s)"

echo ""
echo "[4/6] Installing radio binaries..."
for binary_info in "mpg123_bin:$SHA256_MPG123_BIN" "alsa_play:$SHA256_ALSA_PLAY"; do
    binary="${binary_info%%:*}"; sha="${binary_info##*:}"
    mv "$STAGING_DIR/$binary" "$INSTALL_DIR/$binary"
    verify_installed_sha256 "$INSTALL_DIR/$binary" "$sha" "$binary"
    chmod 755 "$INSTALL_DIR/$binary"
    echo "  $binary installed and verified"
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
_PATCHED=0    # disarm — install succeeded
_PRELOADED=0
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
echo "    _p=\$(mktemp /etc/.ld.so.preload.XXXXXX)"
echo "    grep -v speed_override /etc/ld.so.preload > \"\$_p\" && chmod 644 \"\$_p\" && mv \"\$_p\" /etc/ld.so.preload"
echo "    reboot"
echo "=========================================="
