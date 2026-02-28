Start Docker with:
  su -c /data/adb/docker-ak3/dockerd-v1ns.sh --iptables=false

Docker client socket:
  export DOCKER_HOST=unix:///data/data/com.termux/files/usr/var/run/docker.sock
  export DOCKER_API_VERSION=1.43

Automatic behavior:
  - Magisk service.sh launches /data/adb/docker-ak3/start-dockerd.sh on boot
  - the starter waits for Termux's dockerd and unshare binaries to become available after user unlock
  - Termux and SSH login shells export DOCKER_HOST and DOCKER_API_VERSION automatically via profile.d
  - the shell profile defines a `docker()` wrapper that starts dockerd on demand and waits briefly for the socket
  - plain `docker ...` should work from Termux and SSH without manual export or manual daemon startup

Compose compatibility:
  - The bundled Docker daemon exposes API v1.43.
  - Newer Docker Compose clients may default to a newer API and fail unless DOCKER_API_VERSION=1.43 is set.

Storage driver:
  - The packaged daemon uses `vfs` with `/data/local/tmp/docker-root-vfs`.
  - This avoids Android/f2fs issues seen with `overlay2` on some images.

Seccomp note:
  - Debian/Ubuntu/glibc-based images may fail under the default seccomp profile on this Android setup.
  - For `docker run`, use `--security-opt seccomp=unconfined`.
  - For Compose, add:
      security_opt:
        - seccomp=unconfined
