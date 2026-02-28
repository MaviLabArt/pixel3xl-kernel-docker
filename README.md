# Pixel 3 XL Docker Kernel

This repo rebuilds a Docker-capable AnyKernel3 package for the Google Pixel 3 XL (`crosshatch`) on LineageOS 22.2 / Android 15.

What it preserves:
- the LineageOS `crosshatch` kernel base from `lineage-22.2`
- the working `v10` Docker userspace integration validated on-device

What it changes:
- enables the kernel-side Docker features missing from stock
- builds Wi-Fi and audio into the kernel image so early-loaded vendor modules are not replaced by AnyKernel
- packages the working Magisk helper flow for seamless `docker` use from SSH and Termux

## Local build

Run:

```sh
./scripts/build_latest_crosshatch_docker_kernel.sh
```

The script:
- queries the latest official LineageOS `crosshatch` nightly metadata
- fetches `origin/lineage-22.2` for the kernel and device repos
- clones those repos automatically into `src/` if missing
- rebuilds the kernel in a disposable worktree
- emits a flashable AnyKernel3 zip and `.sha256` in the repo root

## GitHub Actions

Workflow:
- `.github/workflows/crosshatch-docker-kernel.yml`

Model:
- detect latest nightly on GitHub-hosted Ubuntu
- build on a self-hosted Linux runner
- publish the zip and checksum as a GitHub Release

See:
- [GITHUB_ACTIONS.md](GITHUB_ACTIONS.md)

## Source-matching note

This repo follows the practical workflow:
- latest published `crosshatch` nightly metadata
- latest fetched `origin/lineage-22.2` branch heads

It does not reconstruct LineageOS's exact internal source snapshot for each nightly.
