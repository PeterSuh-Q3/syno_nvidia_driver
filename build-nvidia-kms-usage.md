# NVIDIA 580 KMS focused build guide

This guide describes how to reproduce the focused DSM 7.4 / kernel 5.10.55
NVIDIA 580.173.02 proprietary KMS diagnostic build for `epyc7002` and
`epyc7003`. It is a build and ABI-validation workflow, not a release process.
It does not upload or replace assets in the `nvidia` release.

## What the build does

The focused build uses the matching Synology kernel/toolchain tree in the
pinned `dante90/syno-compiler` image, the platform-specific provider
`Module.symvers`, six selected DRM/DMA-BUF headers, and the local
`drm-provider-symbol-aliases.h` shim. It enables `CONFIG_DRM_MODULE` in the
disposable container layer, sets `NO_BACKLIGHT=1`, and builds with 12 jobs.
`build-nvidia.sh` passes `KBUILD_EXTRA_SYMBOLS` and `EXTRA_CFLAGS` explicitly
to Kbuild so they reach the nested module build.

The output is checked for platform, driver/kernel version, `nvidia-drm.ko`
vermagic, the `modeset` parameter, and coverage of DRM/provider imports by
that platform's symbol table.

## Local build with Docker Desktop

From the repository root, make sure Docker Desktop is running and the NVIDIA
580.173.02 installer is present at:

```text
run/NVIDIA-Linux-x86_64-580.173.02.run
```

The script verifies the installer SHA-256 before building. Build one platform
at a time:

```bash
scripts/build-nvidia-kms-focused3.sh epyc7002
scripts/build-nvidia-kms-focused3.sh epyc7003
```

Each invocation creates a timestamped directory under
`out/kms-focused3-repro/<UTC timestamp>/<platform>/`, containing the build log
and candidate archives. The kernel archive is named
`nv-ko-580.173.02-proprietary-<platform>-51055.tgz`. The script runs the
validator automatically and prints the archive SHA-256. These are diagnostic
candidates; do not copy them into `out/release-assets-nvidia/` or publish them
as releases without separate review and device testing.

## Reproduce from GitHub Actions

The manually dispatched workflow is:

```text
.github/workflows/reproduce-nvidia-580-kms-focused3.yml
```

In GitHub, open **Actions → Reproduce NVIDIA 580 Proprietary KMS focused3
diagnostics → Run workflow**, then select `epyc7002`, `epyc7003`, or `both`.
The workflow downloads the NVIDIA installer, verifies its pinned SHA-256,
builds inside the pinned compiler image, runs the same validation, and uploads
the logs and candidate files as a workflow artifact. Artifacts are retained for
30 days. The workflow has read-only repository permissions and does not create
commits, tags, or release assets.

## What the result proves—and does not prove

A successful run proves that the selected source and pinned build inputs
produce a kernel module pack that passes the scripted metadata and symbol
coverage checks. It does not prove runtime KMS operation on every platform.
EPYC7002 has a historical device-tested canonical pack, but the focused3
rebuild is not byte-identical to that canonical pack. EPYC7003's focused3
result is compile/ABI evidence only until tested on a matching physical DSM
system. Keep those distinctions when comparing hashes or describing support.

The current local reproduction (2026-10-16) completed and passed the
validator on both targets:

| Platform | Candidate archive SHA-256 | Result |
| --- | --- | --- |
| `epyc7002` | `1ca841a8827c887bae4686bcff7a5217d5e4bc37a81d1f5b5c686f1acaafc04d` | Build and scripted ABI checks passed; historical device-tested canonical archive remains a separate artifact. |
| `epyc7003` | `4047e099327b039f970d48c79ce8d96075210374d5ce2897aa246e45a1828290` | Build and scripted ABI checks passed; no matching-device runtime KMS test is claimed. |

The shared userspace archive produced in both runs had SHA-256
`1df12489d5ecfb1be50fc520f1411cbf346bfbddec71f9456bb146b5cfe88438`.
