export DOCKER_HOST=unix:///data/data/com.termux/files/usr/var/run/docker.sock
export DOCKER_API_VERSION=1.43

docker_ak3_socket=/data/data/com.termux/files/usr/var/run/docker.sock
docker_ak3_starter=/data/adb/docker-ak3/start-dockerd.sh

docker_ak3_ensure() {
  if pidof dockerd >/dev/null 2>&1 && [ -S "$docker_ak3_socket" ]; then
    return 0
  fi

  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo -n sh "$docker_ak3_starter" >/dev/null 2>&1 &
  fi

  i=0
  while [ "$i" -lt 25 ]; do
    if [ -S "$docker_ak3_socket" ]; then
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done

  return 0
}

docker() {
  docker_ak3_ensure
  command docker "$@"
}
