#!/system/bin/sh

set -eu

PREFIX=/data/data/com.termux/files/usr
WRAPPER=/data/adb/docker-ak3/dockerd-v1ns.sh
DOCKERD_BIN=$PREFIX/bin/dockerd
UNSHARE_BIN=$PREFIX/bin/unshare
SOCK=$PREFIX/var/run/docker.sock
LOGFILE=/data/local/tmp/docker-ak3-service.log
LOCKDIR=/data/local/tmp/docker-ak3-start.lock

log_msg() {
  if command -v log >/dev/null 2>&1; then
    log -t docker-ak3 "$1"
  fi
}

ensure_dirs() {
  mkdir -p "$PREFIX/var/run" /data/local/tmp/docker-root /data/local/tmp/docker-exec
}

daemon_ready() {
  pidof dockerd >/dev/null 2>&1 && [ -S "$SOCK" ]
}

wait_for_termux_bins() {
  i=0
  while [ "$i" -lt 180 ]; do
    if [ -x "$WRAPPER" ] && [ -x "$DOCKERD_BIN" ] && [ -x "$UNSHARE_BIN" ]; then
      return 0
    fi
    i=$((i + 1))
    sleep 2
  done
  return 1
}

ensure_dirs

if daemon_ready; then
  exit 0
fi

if ! mkdir "$LOCKDIR" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$LOCKDIR" 2>/dev/null || true' EXIT INT TERM

if daemon_ready; then
  exit 0
fi

if ! wait_for_termux_bins; then
  log_msg "dockerd binaries unavailable after wait; skipping start"
  exit 0
fi

if ! pidof dockerd >/dev/null 2>&1; then
  rm -f "$SOCK"
fi

nohup env DOCKERD_BIN="$DOCKERD_BIN" PATH="$PREFIX/bin:/system/bin:/system/xbin:/vendor/bin" \
  "$WRAPPER" --iptables=false >>"$LOGFILE" 2>&1 &

i=0
while [ "$i" -lt 30 ]; do
  if [ -S "$SOCK" ]; then
    chmod 0666 "$SOCK"
    exit 0
  fi
  i=$((i + 1))
  sleep 1
done

log_msg "dockerd did not create socket in time"
exit 0
