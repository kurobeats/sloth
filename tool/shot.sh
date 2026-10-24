#!/bin/bash
# Boot the Linux bundle under Xvfb and capture a screenshot.
# usage: shot.sh <out.png> [seconds]
set -u
OUT=${1:-/tmp/shot.png}
WAIT=${2:-10}
export DISPLAY=:99
pkill -x sloth 2>/dev/null
sleep 1
pgrep -f "openbox" >/dev/null || (setsid openbox >/tmp/openbox.log 2>&1 &)
sleep 1
cd /home/ants/Documents/sloth
setsid env LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe GDK_BACKEND=x11 \
  ./build/linux/x64/debug/bundle/sloth >/tmp/sloth-run.log 2>&1 </dev/null &
sleep "$WAIT"
xwininfo -root -children 2>&1 | head -6
import -window root "$OUT" && echo "shot: $OUT"
tail -3 /tmp/sloth-run.log
