#!/bin/sh
# Read volume 0-100 from conf, convert to mpg123 scale 0-32768
VOL=$(cat /mnt/data/radio_volume.conf 2>/dev/null | tr -cd '0-9' | head -c 3)
[ -z "$VOL" ] && VOL=80
SCALE=$(( VOL * 328 ))
[ $SCALE -gt 32768 ] && SCALE=32768
exec /mnt/data/mpg123_bin --scale $SCALE "$@"
