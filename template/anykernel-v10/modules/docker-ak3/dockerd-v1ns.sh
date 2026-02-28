#!/system/bin/sh

set -eu

PREFIX=${PREFIX:-/data/data/com.termux/files/usr}
export PREFIX
export PATH="$PREFIX/bin:/system/bin:/system/xbin:/vendor/bin"
export TMPDIR="${TMPDIR:-$PREFIX/tmp}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-$PREFIX/lib}"
export HOME="${HOME:-/data/data/com.termux/files/home}"

log_msg() {
  if [ -x /system/bin/log ]; then
    /system/bin/log -t dockerd-v1ns "$1"
  fi
  if [ -e /dev/kmsg ]; then
    echo "<6>dockerd-v1ns: $1" > /dev/kmsg 2>/dev/null
  fi
}

main() {
  dockerd_bin="${DOCKERD_BIN:-}"
  config_file="${DOCKER_AK3_CONFIG:-/data/adb/docker-ak3/daemon-localtmp.json}"
  if [ -z "$dockerd_bin" ]; then
    if command -v dockerd >/dev/null 2>&1; then
      dockerd_bin=$(command -v dockerd)
    else
      dockerd_bin="$PREFIX/bin/dockerd"
    fi
  fi

  if [ ! -x "$dockerd_bin" ]; then
    log_msg "dockerd binary not found at $dockerd_bin"
    echo "dockerd binary not found at $dockerd_bin" >&2
    exit 1
  fi

  exec unshare -m --propagation private /system/bin/sh -s -- "$dockerd_bin" "$config_file" "$@" <<'EOF'
set -eu

DOCKERD_BIN="$1"
CONFIG_FILE="$2"
shift 2

PATH=/data/data/com.termux/files/usr/bin:/system/bin:/system/xbin:/vendor/bin
export PATH
export PREFIX=/data/data/com.termux/files/usr
export TMPDIR=${TMPDIR:-/data/data/com.termux/files/usr/tmp}
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-/data/data/com.termux/files/usr/lib}
export HOME=${HOME:-/data/data/com.termux/files/home}

ensure_dir() {
  [ -d "$1" ] || mkdir -p "$1"
}

umount_matches() {
  for target in "$@"; do
    umount -l "$target" >/dev/null 2>&1 || true
  done
}

umount_cgroup_tree() {
  awk '$5 ~ "^/sys/fs/cgroup(/.*)?$" { print $5 }' /proc/self/mountinfo | sort -r | while read -r mountpoint; do
    umount -l "$mountpoint" >/dev/null 2>&1 || true
  done
}

mount_named_controller() {
  name="$1"
  opts="$2"
  path="$3"
  ensure_dir "$path"
  mount -t cgroup -o "$opts" "$name" "$path"
}

mount_cpu_pair() {
  ensure_dir /sys/fs/cgroup/cpu
  ensure_dir /sys/fs/cgroup/cpuacct
  ensure_dir /sys/fs/cgroup/cpu,cpuacct

  if mount -t cgroup -o cpu,cpuacct cpu,cpuacct /sys/fs/cgroup/cpu,cpuacct; then
    mount /sys/fs/cgroup/cpu,cpuacct /sys/fs/cgroup/cpu
    mount /sys/fs/cgroup/cpu,cpuacct /sys/fs/cgroup/cpuacct
    return 0
  fi

  mount_named_controller cpu cpu /sys/fs/cgroup/cpu
  mount_named_controller cpuacct cpuacct /sys/fs/cgroup/cpuacct
}

umount_matches /dev/blkio /dev/cpuctl /dev/cpuset /dev/memcg /dev/stune
umount_cgroup_tree
ensure_dir /sys/fs/cgroup
mount -t tmpfs -o rw,nosuid,nodev,noexec,relatime,mode=0755 cgroup_root /sys/fs/cgroup

mount_named_controller blkio blkio /sys/fs/cgroup/blkio
mount_cpu_pair
mount_named_controller cpuset cpuset /sys/fs/cgroup/cpuset
mount_named_controller devices devices /sys/fs/cgroup/devices
mount_named_controller freezer freezer /sys/fs/cgroup/freezer
mount_named_controller memory memory /sys/fs/cgroup/memory
mount_named_controller pids pids /sys/fs/cgroup/pids
mount_named_controller schedtune schedtune /sys/fs/cgroup/schedtune >/dev/null 2>&1 || true

if [ -f "$CONFIG_FILE" ]; then
  exec "$DOCKERD_BIN" --exec-opt native.cgroupdriver=cgroupfs --config-file "$CONFIG_FILE" "$@"
fi

exec "$DOCKERD_BIN" --exec-opt native.cgroupdriver=cgroupfs "$@"
EOF
}

main "$@"
