#!/bin/bash
# OXWU startup script - patched for HAOS 17.3+ Electron sandbox compatibility
# See: addon Dockerfile comments for full explanation
set -e

mkdir -p /tmp
echo "CUSTOM_STARTUP ENTERED $(date)" >> /tmp/custom_startup.log

LD_LIBRARY_PATH="${LD_LIBRARY_PATH//\/usr\/lib\/arm-linux-gnueabihf:/}"
LD_LIBRARY_PATH="${LD_LIBRARY_PATH//:\/usr\/lib\/arm-linux-gnueabihf/}"
LD_LIBRARY_PATH="${LD_LIBRARY_PATH//\/usr\/lib\/arm-linux-gnueabihf/}"
export LD_LIBRARY_PATH

OXWU_ALERT_INTENSITY=$(grep oxwu_alert_intensity /data/options.json 2>/dev/null | cut -d: -f2 | tr -d '" ,')

[ -f /app/notify.sh ] && chmod a+x /app/notify.sh
[ -f /config/config/oxwu/notify.sh ] && chmod a+x /config/config/oxwu/notify.sh

mkdir -p /home/kasm-user/.config/oxwu/
[ -f /tmp/settings.json ] && cp /tmp/settings.json /home/kasm-user/.config/oxwu/settings.json
[ -f /config/config/oxwu/settings.json ] && cp /config/config/oxwu/settings.json /home/kasm-user/.config/oxwu/settings.json
[ "x$OXWU_ALERT_INTENSITY" != "x" ] && \
    sed -i "s/\"alertIntensity\":.*/\"alertIntensity\": $OXWU_ALERT_INTENSITY,/g" \
        /home/kasm-user/.config/oxwu/settings.json

# Fix /home/kasm-user permissions (kasm-user needs to write SingletonLock, etc.)
chown -R kasm-user:kasm-user /home/kasm-user 2>/dev/null
chmod -R u+rwX /home/kasm-user 2>/dev/null

# Keep Kasm's monitored custom-startup service alive unless autorun is a
# literal JSON boolean true.
SETTINGS_FILE=/home/kasm-user/.config/oxwu/settings.json
if ! python3 - "$SETTINGS_FILE" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as settings_file:
        settings = json.load(settings_file)
except (OSError, ValueError):
    raise SystemExit(1)

raise SystemExit(
    0 if isinstance(settings, dict) and settings.get("autorun") is True else 1
)
PY
then
    exec sleep infinity
fi

if [ ! -x /opt/oxwu-extracted/AppRun ]; then
    exec sleep infinity
fi

# Run as kasm-user after XFCE is available. A portable mkdir lock prevents
# concurrent startup hooks from creating duplicate OXWU processes.
echo "ABOUT TO EXEC RUNUSER $(date)" >> /tmp/custom_startup.log
exec runuser -u kasm-user -- env APPDIR=/opt/oxwu-extracted HERE=/opt/oxwu-extracted bash -c '
set -eu

/usr/bin/desktop_ready

if pgrep -u "$(id -u)" -x oxwu >/dev/null; then
    exec sleep infinity
fi

LOCK_DIR=/home/kasm-user/.cache/oxwu/autorun.lock
mkdir -p /home/kasm-user/.cache/oxwu

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    if [ ! -r "$LOCK_DIR/pid" ]; then
        exec sleep infinity
    fi

    LOCK_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
    case "$LOCK_PID" in
        ""|*[!0-9]*) exec sleep infinity ;;
    esac

    if kill -0 "$LOCK_PID" 2>/dev/null; then
        exec sleep infinity
    fi

    rm -f "$LOCK_DIR/pid"
    rmdir "$LOCK_DIR" 2>/dev/null || exec sleep infinity
    mkdir "$LOCK_DIR" 2>/dev/null || exec sleep infinity
fi

printf "%s\n" "$$" > "$LOCK_DIR/pid"

cd /opt/oxwu-extracted
./AppRun --no-sandbox --hidden &
OXWU_PID=$!
wait "$OXWU_PID" || true

rm -f "$LOCK_DIR/pid"
rmdir "$LOCK_DIR" 2>/dev/null || true
exec sleep infinity
'
