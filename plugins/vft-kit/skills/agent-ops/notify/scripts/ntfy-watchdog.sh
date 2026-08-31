#!/bin/sh
# Keep ntfy-macos running and restart a stale subscriber after its startup grace period.

APP=${NTFY_MACOS_APP:-/Applications/ntfy-macos.app}
BIN=${NTFY_MACOS_BIN:-$APP/Contents/MacOS/ntfy-macos}
GRACE=${NTFY_MACOS_GRACE_SECONDS:-120}

case "$GRACE" in
  ''|*[!0-9]*) echo "NTFY_MACOS_GRACE_SECONDS must be a non-negative integer" >&2; exit 2 ;;
esac

if [ ! -x "$BIN" ]; then
  echo "ntfy-macos executable not found: $BIN" >&2
  exit 1
fi

PID=$(/usr/bin/pgrep -f "^$BIN$" | /usr/bin/head -n 1)
if [ -z "$PID" ]; then
  echo "$(date '+%F %T') started (not-running)"
  /usr/bin/open "$APP"
  exit 0
fi

CONNECTIONS=$(/usr/sbin/lsof -nP -iTCP -a -p "$PID" 2>/dev/null | /usr/bin/grep -c ESTABLISHED)
[ "$CONNECTIONS" -gt 0 ] && exit 0

# A fresh process may not have established its subscription yet.
UPTIME=$(/bin/ps -o etime= -p "$PID" | /usr/bin/awk -F'[-:]' '{s=0; for(i=1;i<=NF;i++) s=s*60+$i; print s}')
[ "$UPTIME" -le "$GRACE" ] && exit 0

echo "$(date '+%F %T') restarted pid=$PID (subscription-dead, uptime=${UPTIME}s, conns=$CONNECTIONS)"
/bin/kill "$PID" 2>/dev/null
/bin/sleep 2
/usr/bin/open "$APP"
