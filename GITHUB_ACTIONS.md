GitHub Actions workflow:
- `.github/workflows/crosshatch-docker-kernel.yml`

What it does:
- checks the latest official LineageOS `crosshatch` nightly every 6 hours
- skips if a GitHub Release for that nightly tag already exists
- builds the Docker-enabled AnyKernel3 package with the same `v10` kernel and userspace logic
- publishes the zip and `.sha256` as a GitHub Release

Runner model:
- `detect` and `publish` run on GitHub-hosted Ubuntu
- `build` runs on a self-hosted Linux runner

Self-hosted runner requirements:
- Linux runner with `self-hosted` and `linux` labels
- enough free disk for kernel source + output
- `sudo` available to install dependencies automatically, or preinstalled equivalents
- enough RAM/CPU for a 4.9 kernel build

Dependency install behavior:
- the workflow can install dependencies automatically through:
  - `apt`
  - `pacman`
- if your runner uses something else, preinstall:
  - `git`
  - `python3`
  - `clang`
  - `lz4`
  - `zip`
  - `aarch64-linux-gnu` binutils
  - `arm-none-eabi` binutils

Manual trigger:
- use `workflow_dispatch`
- `force_build=true` ignores the existing-release guard
- `install_deps=false` skips the dependency installation step

Release tagging:
- one release per latest Lineage nightly
- tag format: `crosshatch-YYYYMMDD`

Source-matching note:
- this workflow builds against the latest fetched `origin/lineage-22.2` heads at runtime
- it uses the latest published nightly metadata for naming and targeting
- it does not reproduce Lineage's exact internal source snapshot for that nightly
