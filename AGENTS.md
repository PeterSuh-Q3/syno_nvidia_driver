# Repository instructions

## Shared NVIDIA layers — mandatory build invariant

- Keep exactly one `nv-userspace-<version>.tgz` and one `nv-gsp-<version>.tgz`
  per driver version under `out/release-assets-nvidia/shared/<major>/`.
  These layers are version-specific, but **not** platform- or flavor-specific.
- A kernel-module build must read the shared userspace archive. Never rebuild
  or copy it into a timestamped/platform `out/` directory. To introduce a new
  version, bootstrap its shared userspace archive once with
  `NV_CREATE_SHARED_USERSPACE=1`, then build all platforms without that flag.
- SPK packaging must extract the shared userspace/GSP archives directly. Do
  not retain copies in `work/spk-*/dl/`, even as download caches. A missing
  shared archive may be downloaded or created **once at the shared path**.
- Before calling a build or cleanup complete, run
  `scripts/check-shared-nvidia-layers.sh`. It must report no versioned
  userspace/GSP `.tgz` outside `out/release-assets-nvidia/shared/` in `out/`
  or `work/`. Do not commit or publish duplicated layers.

## NVIDIA driver package descriptions

- For K5 NVIDIA driver SPKs, do not mention `DSM 7.2` (or another DSM minimum)
  in the user-visible package description. Keep the compatibility metadata such
  as `os_min_ver` unchanged unless the requested compatibility range itself is
  being changed.
- The package description should still identify the driver flavor/version,
  CUDA API version, supported GPU range, kernel version, and bundled platforms.
