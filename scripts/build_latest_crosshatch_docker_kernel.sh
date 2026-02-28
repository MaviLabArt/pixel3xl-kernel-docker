#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="crosshatch"
LINEAGE_BRANCH="${LINEAGE_BRANCH:-lineage-22.2}"
VERSION_TAG="${VERSION_TAG:-v10}"
ANDROID_VERSION="${ANDROID_VERSION:-15}"
KERNEL_REPO="${KERNEL_REPO:-$ROOT_DIR/src/android_kernel_google_msm-4.9}"
DEVICE_REPO="${DEVICE_REPO:-$ROOT_DIR/src/android_device_google_crosshatch}"
KERNEL_REMOTE_URL="${KERNEL_REMOTE_URL:-https://github.com/LineageOS/android_kernel_google_msm-4.9.git}"
DEVICE_REMOTE_URL="${DEVICE_REMOTE_URL:-https://github.com/LineageOS/android_device_google_crosshatch.git}"
FRAGMENT_FILE="${FRAGMENT_FILE:-$ROOT_DIR/docker.fragment}"
TEMPLATE_DIR="${TEMPLATE_DIR:-$ROOT_DIR/template/anykernel-v10}"
RUNS_DIR="${RUNS_DIR:-$ROOT_DIR/auto-build-runs}"
LOCALTC_DIR="${LOCALTC_DIR:-$ROOT_DIR/localtc}"
TOOLWRAP_DIR="${TOOLWRAP_DIR:-$ROOT_DIR/toolwrap-auto}"
JOBS="${JOBS:-$(nproc)}"
KCFLAGS_VALUE="${KCFLAGS_VALUE:--Wno-error -Wno-error=strict-prototypes -Wno-error=array-parameter -Wno-error=implicit-enum-enum-cast -Wno-error=default-const-init-field-unsafe -Wno-error=default-const-init-var-unsafe}"

info() {
  printf '[*] %s\n' "$*"
}

die() {
  printf '[!] %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

for cmd in git python clang make zip lz4; do
  need_cmd "$cmd"
done

[ -f "$FRAGMENT_FILE" ] || die "config fragment not found: $FRAGMENT_FILE"
[ -d "$TEMPLATE_DIR" ] || die "template dir not found: $TEMPLATE_DIR"

ensure_repo() {
  local repo_dir="$1"
  local remote_url="$2"
  local branch="$3"

  if [ -d "$repo_dir/.git" ]; then
    return 0
  fi

  info "Cloning $(basename "$repo_dir") from $remote_url"
  mkdir -p "$(dirname "$repo_dir")"
  git clone --branch "$branch" --single-branch "$remote_url" "$repo_dir"
}

fetch_latest_build_meta() {
  python - <<'PY'
import json
import shlex
import urllib.request

url = "https://download.lineageos.org/api/v2/devices/crosshatch/builds"
with urllib.request.urlopen(url, timeout=30) as response:
    builds = json.load(response)

if not isinstance(builds, list) or not builds:
    raise SystemExit("no builds returned by Lineage API")

latest = builds[0]
files = latest.get("files", [])
ota = next((f for f in files if f.get("filename", "").endswith("-signed.zip")), None)
boot = next((f for f in files if f.get("filename") == "boot.img"), None)

if ota is None:
    raise SystemExit("latest build is missing signed ota zip metadata")

values = {
    "LINEAGE_VERSION": latest["version"],
    "LINEAGE_BUILD_DATE": latest["date"],
    "LINEAGE_BUILD_STAMP": latest["date"].replace("-", ""),
    "LINEAGE_BUILD_FILENAME": ota["filename"],
    "LINEAGE_BUILD_URL": ota["url"],
    "LINEAGE_OS_PATCH_LEVEL": latest["os_patch_level"],
    "LINEAGE_OS_PATCH_MONTH": latest["os_patch_level"][:7],
    "LINEAGE_BOOT_URL": boot["url"] if boot else "",
}

for key, value in values.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
}

prepare_toolwrap() {
  local bin_dir="$TOOLWRAP_DIR/bin"
  mkdir -p "$bin_dir"

  local aarch64_src arm32_src
  if [ -d "$LOCALTC_DIR/usr/bin" ]; then
    aarch64_src="$LOCALTC_DIR/usr/bin"
    arm32_src="$LOCALTC_DIR/usr/bin"
  else
    command -v aarch64-linux-gnu-ld >/dev/null 2>&1 || die "missing aarch64-linux-gnu binutils; install them or provide LOCALTC_DIR"
    command -v arm-none-eabi-ld >/dev/null 2>&1 || die "missing arm-none-eabi binutils; install them or provide LOCALTC_DIR"
    aarch64_src="$(dirname "$(command -v aarch64-linux-gnu-ld)")"
    arm32_src="$(dirname "$(command -v arm-none-eabi-ld)")"
  fi

  local f base
  for f in "$aarch64_src"/aarch64-linux-gnu-*; do
    [ -e "$f" ] || continue
    ln -sf "$f" "$bin_dir/$(basename "$f")"
  done

  for f in "$arm32_src"/arm-none-eabi-*; do
    [ -e "$f" ] || continue
    base="${f##*/arm-none-eabi-}"
    cat >"$bin_dir/arm-linux-androideabi-$base" <<EOF
#!/bin/sh
exec $f "\$@"
EOF
    chmod 0755 "$bin_dir/arm-linux-androideabi-$base"
  done

  cat >"$bin_dir/aarch64-linux-gnu-gcc" <<'EOF'
#!/bin/sh
exec clang --target=aarch64-linux-gnu -no-integrated-as "$@"
EOF
  chmod 0755 "$bin_dir/aarch64-linux-gnu-gcc"

  cat >"$bin_dir/aarch64-linux-gnu-cpp" <<'EOF'
#!/bin/sh
exec clang --target=aarch64-linux-gnu -E "$@"
EOF
  chmod 0755 "$bin_dir/aarch64-linux-gnu-cpp"

  cat >"$bin_dir/arm-linux-androideabi-gcc" <<'EOF'
#!/bin/sh
exec clang --target=arm-linux-androideabi -march=armv7-a -mthumb -no-integrated-as "$@"
EOF
  chmod 0755 "$bin_dir/arm-linux-androideabi-gcc"

  cat >"$bin_dir/arm-linux-androideabi-cpp" <<'EOF'
#!/bin/sh
exec clang --target=arm-linux-androideabi -E "$@"
EOF
  chmod 0755 "$bin_dir/arm-linux-androideabi-cpp"
}

apply_source_patches() {
  local kernel_dir="$1"
  KERNEL_DIR="$kernel_dir" python - <<'PY'
from pathlib import Path
import os

kernel_dir = Path(os.environ["KERNEL_DIR"])

def replace_once(path_str, old, new):
    path = kernel_dir / path_str
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"expected text not found in {path}")
    path.write_text(text.replace(old, new, 1))

replace_once(
    "Makefile",
    "ifneq ($(GCC_TOOLCHAIN),)\nCLANG_FLAGS\t+= --gcc-toolchain=$(GCC_TOOLCHAIN)\nendif\nCLANG_FLAGS\t+= -no-integrated-as\nCLANG_FLAGS\t+= -Werror=unknown-warning-option\n",
    "ifneq ($(GCC_TOOLCHAIN),)\nCLANG_FLAGS\t+= --gcc-toolchain=$(GCC_TOOLCHAIN)\nendif\nifneq ($(LLVM_IAS),1)\nCLANG_FLAGS\t+= -no-integrated-as\nendif\nCLANG_FLAGS\t+= -Werror=unknown-warning-option\n",
)

replace_once(
    "arch/arm64/kernel/vdso32/Makefile",
    "ifeq ($(cc-name),clang)\n  CC_ARM32 := $(CC) $(CLANG_TARGET_ARM32) -no-integrated-as $(CLANG_GCC32_TC) $(CLANG_PREFIX32)\n  GCC_ARM32_TC := $(realpath $(dir $(shell which $(CROSS_COMPILE_ARM32)ld))/..)\n",
    "ifeq ($(cc-name),clang)\n  ifneq ($(LLVM_IAS),1)\n    CC_ARM32 := $(CC) $(CLANG_TARGET_ARM32) -no-integrated-as $(CLANG_GCC32_TC) $(CLANG_PREFIX32)\n  else\n    CC_ARM32 := $(CC) $(CLANG_TARGET_ARM32) $(CLANG_GCC32_TC) $(CLANG_PREFIX32)\n  endif\n  GCC_ARM32_TC := $(realpath $(dir $(shell which $(CROSS_COMPILE_ARM32)ld))/..)\n",
)

gcc_wrapper = kernel_dir / "scripts/gcc-wrapper.py"
gcc_text = gcc_wrapper.read_text()
gcc_text = gcc_text.replace("#! /usr/bin/env python2", "#! /usr/bin/env python3", 1)
gcc_text = gcc_text.replace(
    '        print >> sys.stderr, "error, forbidden warning:", m.group(2)\n',
    '        print("error, forbidden warning:", m.group(2), file=sys.stderr)\n',
)
gcc_text = gcc_text.replace(
    '            print >> sys.stderr, line,\n            interpret_warning(line)\n',
    '            text = line.decode("utf-8", "replace") if isinstance(line, bytes) else line\n            print(text, end="", file=sys.stderr)\n            interpret_warning(text)\n',
)
gcc_text = gcc_text.replace(
    "            print >> sys.stderr, args[0] + ':',e.strerror\n            print >> sys.stderr, 'Is your PATH set correctly?'\n",
    "            print(f\"{args[0]}: {e.strerror}\", file=sys.stderr)\n            print('Is your PATH set correctly?', file=sys.stderr)\n",
)
gcc_text = gcc_text.replace(
    "            print >> sys.stderr, ' '.join(args), str(e)\n",
    "            print(' '.join(args), str(e), file=sys.stderr)\n",
)
gcc_text = gcc_text.replace(
    "def interpret_warning(line):\n    \"\"\"Decode the message from gcc.  The messages we care about have a filename, and a warning\"\"\"\n    line = line.rstrip('\\n')\n    m = warning_re.match(line)\n    if m and m.group(2) not in allowed_warnings:\n        print(\"error, forbidden warning:\", m.group(2), file=sys.stderr)\n\n        # If there is a warning, remove any object if it exists.\n        if ofile:\n            try:\n                os.remove(ofile)\n            except OSError:\n                pass\n        sys.exit(1)\n",
    "def interpret_warning(line):\n    return\n",
)
gcc_wrapper.write_text(gcc_text)

audio_path = kernel_dir / "techpack/audio/config/b1c1auto.conf"
audio_text = audio_path.read_text()
for name in [
    "CONFIG_PINCTRL_WCD",
    "CONFIG_SND_SOC_WCD9XXX_V2",
    "CONFIG_SND_SOC_WCD_SPI",
    "CONFIG_SND_SOC_WCD934X",
    "CONFIG_WCD9XXX_CODEC_CORE",
    "CONFIG_MSM_CDC_PINCTRL",
    "CONFIG_SND_SOC_MACHINE_SDM845",
    "CONFIG_WCD_DSP_GLINK",
    "CONFIG_SND_SOC_MAX98927",
    "CONFIG_SND_SOC_CS35L36",
    "CONFIG_SND_SOC_MACHINE_SDM845_MAX98927",
]:
    audio_text = audio_text.replace(f"{name}=m", f"{name}=y")
audio_path.write_text(audio_text)
PY
}

configure_kernel() {
  local kernel_dir="$1"
  local out_dir="$2"
  local make_env=(
    PATH="$TOOLWRAP_DIR/bin:$PATH"
    ARCH=arm64
    LLVM_IAS=0
    CLANG_TRIPLE=aarch64-linux-gnu-
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_ARM32=arm-linux-androideabi-
    CC=clang
    LD=aarch64-linux-gnu-ld
    AR=aarch64-linux-gnu-ar
    NM=aarch64-linux-gnu-nm
    OBJCOPY=aarch64-linux-gnu-objcopy
    OBJDUMP=aarch64-linux-gnu-objdump
    STRIP=aarch64-linux-gnu-strip
    KCFLAGS="$KCFLAGS_VALUE"
  )

  rm -rf "$out_dir"
  mkdir -p "$out_dir"

  info "Configuring kernel"
  env "${make_env[@]}" make -C "$kernel_dir" O="$out_dir" bonito_defconfig
  env PATH="$TOOLWRAP_DIR/bin:$PATH" ARCH=arm64 \
    "$kernel_dir/scripts/kconfig/merge_config.sh" -m -O "$out_dir" "$out_dir/.config" "$FRAGMENT_FILE"
  "$kernel_dir/scripts/config" --file "$out_dir/.config" \
    -d LTO \
    -d LTO_CLANG \
    -d CFI \
    -d CFI_PERMISSIVE \
    -d CFI_CLANG \
    -d CFI_CLANG_SHADOW
  env "${make_env[@]}" make -C "$kernel_dir" O="$out_dir" olddefconfig
}

build_kernel() {
  local kernel_dir="$1"
  local out_dir="$2"
  local log_file="$3"
  local make_env=(
    PATH="$TOOLWRAP_DIR/bin:$PATH"
    ARCH=arm64
    LLVM_IAS=0
    CLANG_TRIPLE=aarch64-linux-gnu-
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_ARM32=arm-linux-androideabi-
    CC=clang
    LD=aarch64-linux-gnu-ld
    AR=aarch64-linux-gnu-ar
    NM=aarch64-linux-gnu-nm
    OBJCOPY=aarch64-linux-gnu-objcopy
    OBJDUMP=aarch64-linux-gnu-objdump
    STRIP=aarch64-linux-gnu-strip
    KCFLAGS="$KCFLAGS_VALUE"
  )

  info "Building kernel artifacts"
  env "${make_env[@]}" make -C "$kernel_dir" -j"$JOBS" O="$out_dir" Image.lz4 modules dtbs 2>&1 | tee "$log_file"
}

verify_build() {
  local out_dir="$1"
  local image="$out_dir/arch/arm64/boot/Image.lz4"
  local dtb_v2="$out_dir/arch/arm64/boot/dts/qcom/sdm845-v2.dtb"
  local dtb_v21="$out_dir/arch/arm64/boot/dts/qcom/sdm845-v2.1.dtb"

  [ -f "$image" ] || die "missing Image.lz4"
  [ -f "$dtb_v2" ] || die "missing sdm845-v2.dtb"
  [ -f "$dtb_v21" ] || die "missing sdm845-v2.1.dtb"
  [ ! -f "$out_dir/drivers/staging/qcacld-3.0/wlan.ko" ] || die "qcacld still built as module"
  [ ! -f "$out_dir/techpack/audio/asoc/codecs/snd-soc-wcd934x.ko" ] || die "audio codec still built as module"
  [ ! -f "$out_dir/techpack/audio/asoc/msm/snd-soc-sdm845.ko" ] || die "sdm845 audio machine still built as module"
}

render_anykernel_metadata() {
  local package_dir="$1"
  local kernel_commit="$2"
  local device_commit="$3"
  local out_dir="$4"
  local run_dir="$5"

  PACKAGE_DIR="$package_dir" \
  LINEAGE_VERSION="$LINEAGE_VERSION" \
  LINEAGE_BUILD_DATE="$LINEAGE_BUILD_DATE" \
  LINEAGE_BUILD_STAMP="$LINEAGE_BUILD_STAMP" \
  LINEAGE_BUILD_FILENAME="$LINEAGE_BUILD_FILENAME" \
  LINEAGE_OS_PATCH_MONTH="$LINEAGE_OS_PATCH_MONTH" \
  VERSION_TAG="$VERSION_TAG" \
  KERNEL_COMMIT="$kernel_commit" \
  DEVICE_COMMIT="$device_commit" \
  BUILD_OUT="$out_dir" \
  RUN_DIR="$run_dir" \
  python - <<'PY'
from pathlib import Path
import os
import re

pkg = Path(os.environ["PACKAGE_DIR"])
anykernel = pkg / "anykernel.sh"
text = anykernel.read_text()
text = re.sub(r"## built against LineageOS .* nightly", f"## built against LineageOS {os.environ['LINEAGE_VERSION']} {os.environ['LINEAGE_BUILD_DATE']} nightly", text)
text = re.sub(
    r"kernel\.string=.*",
    f"kernel.string=LineageOS {os.environ['LINEAGE_VERSION']} crosshatch Docker kernel {os.environ['VERSION_TAG']} delayed-start + auto-env ({os.environ['LINEAGE_BUILD_STAMP']})",
    text,
)
text = re.sub(
    r"supported\.patchlevels=.*",
    f"supported.patchlevels={os.environ['LINEAGE_OS_PATCH_MONTH']} - {os.environ['LINEAGE_OS_PATCH_MONTH']}",
    text,
)
text = re.sub(
    r'ui_print "Target: .*"',
    f'ui_print "Target: {os.environ["LINEAGE_BUILD_FILENAME"]}"',
    text,
)
anykernel.write_text(text)

build_info = pkg / "BUILD_INFO.txt"
build_info.write_text(f"""Target device: Google Pixel 3 XL (crosshatch)
ROM target: {os.environ["LINEAGE_BUILD_FILENAME"]}
Android version: 15
Kernel source branch: lineage-22.2
Kernel source commit: {os.environ["KERNEL_COMMIT"]}
Device tree commit: {os.environ["DEVICE_COMMIT"]}
Base defconfig: bonito_defconfig + docker.fragment + b1c1 audio builtin overrides
Build output dir: {os.environ["BUILD_OUT"]}
Run workspace: {os.environ["RUN_DIR"]}

Docker-related kernel features enabled:
- SYSVIPC
- POSIX_MQUEUE
- IPC_NS
- USER_NS
- PID_NS
- CGROUP_PIDS
- CGROUP_DEVICE
- BRIDGE_NETFILTER
- NF_TABLES / NFT_NAT / NFT_MASQ
- IPVLAN / MACVLAN / VXLAN / VLAN_8021Q
- IP_VS / IP_VS_NFCT / RR / TCP / UDP
- IPv6 NAT / MASQUERADE
- xt_addrtype / xt_ipvs

Functional build deltas retained from the working package:
- crosshatch Wi-Fi built into the kernel image (QCA_CLD_WLAN=y)
- crosshatch audio stack built into the kernel image through techpack/audio/config/b1c1auto.conf
- clang 21 compatibility Makefile adjustments for non-integrated assembler usage
- LTO/CFI disabled for this custom build
- AnyKernel3 ak3-helper Magisk module payload for Docker userspace integration
- delayed dockerd start via /data/adb/docker-ak3/start-dockerd.sh
- automatic DOCKER_HOST export for Termux and SSH shells
- on-demand Docker startup via the installed shell profile hook

Packaging:
- AnyKernel3 boot image repack
- Replaces Image.lz4 and dtb
- Does not install /vendor/lib/modules payload
- Adds boot cmdline compatibility flags for legacy Docker userspace checks
- Includes the working v10 Magisk module payload

Practical source note:
- This build uses the latest fetched origin/lineage-22.2 kernel and device branch heads at packaging time.
- It is matched to the latest published LineageOS crosshatch nightly metadata for naming and patchlevel targeting.
""")
PY
}

package_artifacts() {
  local package_dir="$1"
  local out_dir="$2"
  local artifact_zip="$3"
  local sha_file="$4"

  cp "$out_dir/arch/arm64/boot/Image.lz4" "$package_dir/Image.lz4"
  cat \
    "$out_dir/arch/arm64/boot/dts/qcom/sdm845-v2.dtb" \
    "$out_dir/arch/arm64/boot/dts/qcom/sdm845-v2.1.dtb" \
    > "$package_dir/dtb"
  make -s -C "$KERNEL_WORKTREE" O="$out_dir" kernelrelease > "$package_dir/kernel.release"

  (
    cd "$package_dir"
    zip -r -9 "$artifact_zip" \
      anykernel.sh \
      Image.lz4 \
      dtb \
      kernel.release \
      tools \
      META-INF \
      patch \
      ramdisk \
      modules \
      BUILD_INFO.txt
  ) >/dev/null

  sha256sum "$artifact_zip" > "$sha_file"
}

cleanup() {
  if [ -n "${KERNEL_WORKTREE:-}" ] && [ -d "${KERNEL_WORKTREE:-}" ]; then
    git -C "$KERNEL_REPO" worktree remove --force "$KERNEL_WORKTREE" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

ensure_repo "$KERNEL_REPO" "$KERNEL_REMOTE_URL" "$LINEAGE_BRANCH"
ensure_repo "$DEVICE_REPO" "$DEVICE_REMOTE_URL" "$LINEAGE_BRANCH"

eval "$(fetch_latest_build_meta)"

prepare_toolwrap

info "Fetching latest source heads"
git -C "$KERNEL_REPO" fetch --quiet origin "$LINEAGE_BRANCH"
git -C "$DEVICE_REPO" fetch --quiet origin "$LINEAGE_BRANCH"

KERNEL_COMMIT="$(git -C "$KERNEL_REPO" rev-parse "origin/$LINEAGE_BRANCH")"
DEVICE_COMMIT="$(git -C "$DEVICE_REPO" rev-parse "origin/$LINEAGE_BRANCH")"

RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$RUNS_DIR/${DEVICE}-${LINEAGE_BUILD_STAMP}-${RUN_ID}"
KERNEL_WORKTREE="$RUN_DIR/kernel-src"
OUT_DIR="$RUN_DIR/out"
PACKAGE_DIR="$RUN_DIR/package"
LOG_FILE="$RUN_DIR/build.log"

mkdir -p "$RUN_DIR"

info "Preparing detached kernel worktree at $KERNEL_WORKTREE"
git -C "$KERNEL_REPO" worktree add --quiet --detach "$KERNEL_WORKTREE" "$KERNEL_COMMIT"

apply_source_patches "$KERNEL_WORKTREE"
configure_kernel "$KERNEL_WORKTREE" "$OUT_DIR"
build_kernel "$KERNEL_WORKTREE" "$OUT_DIR" "$LOG_FILE"
verify_build "$OUT_DIR"

info "Staging AnyKernel template"
cp -a "$TEMPLATE_DIR/." "$PACKAGE_DIR/"
render_anykernel_metadata "$PACKAGE_DIR" "$KERNEL_COMMIT" "$DEVICE_COMMIT" "$OUT_DIR" "$RUN_DIR"

ARTIFACT_BASENAME="lineage-${LINEAGE_VERSION}-${LINEAGE_BUILD_STAMP}-${DEVICE}-docker-kernel-anykernel3-${VERSION_TAG}.zip"
ARTIFACT_ZIP="$ROOT_DIR/$ARTIFACT_BASENAME"
SHA_FILE="$ROOT_DIR/$ARTIFACT_BASENAME.sha256"

package_artifacts "$PACKAGE_DIR" "$OUT_DIR" "$ARTIFACT_ZIP" "$SHA_FILE"

info "Built artifact: $ARTIFACT_ZIP"
info "Checksum file: $SHA_FILE"
info "Run workspace: $RUN_DIR"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    printf 'artifact_zip=%s\n' "$ARTIFACT_ZIP"
    printf 'artifact_sha256=%s\n' "$SHA_FILE"
    printf 'lineage_build_filename=%s\n' "$LINEAGE_BUILD_FILENAME"
    printf 'lineage_build_stamp=%s\n' "$LINEAGE_BUILD_STAMP"
    printf 'release_tag=%s\n' "${DEVICE}-${LINEAGE_BUILD_STAMP}"
  } >> "$GITHUB_OUTPUT"
fi
