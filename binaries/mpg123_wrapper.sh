#!/bin/sh
VOL=$(tr -cd '0-9' < /mnt/data/radio_volume.conf 2>/dev/null | head -c 3)
VOL=$(printf '%s' "$VOL" | sed 's/^0*//')
case "$VOL" in ''|*[!0-9]*) VOL=50 ;; esac
[ "$VOL" -gt 100 ] 2>/dev/null && VOL=100
SCALE=$(( VOL * 328 ))
[ "$SCALE" -gt 32768 ] && SCALE=32768
exec /mnt/data/mpg123_bin --scale "$SCALE" "$@"
