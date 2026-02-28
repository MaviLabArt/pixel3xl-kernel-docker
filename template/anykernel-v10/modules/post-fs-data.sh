#!/system/bin/sh

MODDIR=${0%/*}
DST=/data/adb/docker-ak3
SRC=$MODDIR/docker-ak3
PROFILE_D=/data/data/com.termux/files/usr/etc/profile.d

mkdir -p "$DST"
mkdir -p "$PROFILE_D"

cp -f "$SRC/dockerd-v1ns.sh" "$DST/dockerd-v1ns.sh"
cp -f "$SRC/start-dockerd.sh" "$DST/start-dockerd.sh"
cp -f "$SRC/daemon-localtmp.json" "$DST/daemon-localtmp.json"
cp -f "$SRC/README.txt" "$DST/README.txt"
cp -f "$SRC/docker-env.sh" "$PROFILE_D/docker-ak3.sh"

chmod 0755 "$DST/dockerd-v1ns.sh"
chmod 0755 "$DST/start-dockerd.sh"
chmod 0644 "$DST/daemon-localtmp.json" "$DST/README.txt"
chmod 0644 "$PROFILE_D/docker-ak3.sh"
chown 0:0 "$DST/dockerd-v1ns.sh" "$DST/start-dockerd.sh" "$DST/daemon-localtmp.json" "$DST/README.txt" 2>/dev/null || true
chown 0:0 "$PROFILE_D/docker-ak3.sh" 2>/dev/null || true

mkdir -p /data/data/com.termux/files/usr/var/run
mkdir -p /data/local/tmp/docker-root /data/local/tmp/docker-exec

if command -v log >/dev/null 2>&1; then
  log -t docker-ak3 "installed dockerd wrapper via ak3-helper module"
fi
