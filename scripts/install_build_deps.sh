#!/usr/bin/env bash

set -euo pipefail

info() {
  printf '[*] %s\n' "$*"
}

if command -v apt-get >/dev/null 2>&1; then
  info "Installing build dependencies with apt"
  sudo apt-get update
  sudo apt-get install -y \
    git \
    python3 \
    clang \
    lz4 \
    zip \
    binutils-aarch64-linux-gnu \
    binutils-arm-none-eabi
  exit 0
fi

if command -v pacman >/dev/null 2>&1; then
  info "Installing build dependencies with pacman"
  sudo pacman -Sy --noconfirm \
    git \
    python \
    clang \
    lz4 \
    zip \
    aarch64-linux-gnu-binutils \
    arm-none-eabi-binutils
  exit 0
fi

printf '[!] Unsupported package manager. Install these manually:\n' >&2
printf '    git python3 clang lz4 zip aarch64-linux-gnu binutils arm-none-eabi binutils\n' >&2
exit 1
