#!/system/bin/sh

MODDIR=${0%/*}
STARTER=/data/adb/docker-ak3/start-dockerd.sh

install_env() {
  PROFILE_D=/data/data/com.termux/files/usr/etc/profile.d
  mkdir -p "$PROFILE_D"
  cp -f "$MODDIR/docker-ak3/docker-env.sh" "$PROFILE_D/docker-ak3.sh"
  chmod 0644 "$PROFILE_D/docker-ak3.sh"
  chown 0:0 "$PROFILE_D/docker-ak3.sh" 2>/dev/null || true
}

install_env

[ -x "$STARTER" ] || exit 0
nohup "$STARTER" >/dev/null 2>&1 &

if command -v log >/dev/null 2>&1; then
  log -t docker-ak3 "requested dockerd auto-start from Magisk service.sh via starter"
fi
