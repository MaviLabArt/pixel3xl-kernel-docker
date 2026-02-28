Start Docker with:
  su -c /data/adb/docker-ak3/dockerd-v1ns.sh --iptables=false

Docker client socket:
  export DOCKER_HOST=unix:///data/data/com.termux/files/usr/var/run/docker.sock

Automatic behavior:
  - Magisk service.sh launches /data/adb/docker-ak3/start-dockerd.sh on boot
  - the starter waits for Termux's dockerd and unshare binaries to become available after user unlock
  - Termux and SSH login shells export DOCKER_HOST automatically via profile.d
  - the shell profile defines a `docker()` wrapper that starts dockerd on demand and waits briefly for the socket
  - plain `docker ...` should work from Termux and SSH without manual export or manual daemon startup
