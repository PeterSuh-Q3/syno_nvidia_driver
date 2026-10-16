# NVIDIA 580 Proprietary KMS: r1000nk successful pilot

## Result and scope

On 2026-10-16, a revised NVIDIA 580.173.02 Proprietary module pack loaded
successfully on a clean-boot DSM 7.4.1 / kernel 5.10.55+ r1000nk test device.
`nvidia.ko`, `nvidia-modeset.ko`, and `nvidia-drm.ko modeset=1` all returned
success. The modeset parameter read `Y`; `/dev/dri/card0` and
`/dev/dri/renderD128` appeared for NVIDIA PCI `0000:01:00.0`. The kernel log
reported `Initialized nvidia-drm ... on minor 0`, with no Oops in the checked
log. This establishes **KMS activation on that device**, not long-term
stability, display-helper output, or compatibility on another platform.

- Pilot archive: `out/r1000nk-kms-abi-fullheaders-v2-20261016/nv-ko-580.173.02-r1000nk-51055.tgz`
- Archive SHA-256: `70c87858f867ff55790e4fbc887079a0cefcfb18aa92f48617abc82d259b3297`
- Extracted `nvidia-drm.ko` SHA-256: `34f74156bc0b6cbb050777ed5abc4eb50a2e521c209b320726ea5f30aa637dcf`
- Shared GSP SHA-256: `39f99970299a398f82b7c6d61a20f22faca1589b044822bdf1e5a36094c7d62b`

This is a pilot artifact, **not** a replacement for any release asset. The
tested modules were staged temporarily on the device; no SPK was built or
release asset changed by this pilot.

## What changed in the build

The earlier r1000nk candidate compiled but Oopsed inside DRM `add_dr` /
`drm_dev_register` as `nvidia-drm.ko modeset=1` loaded. Its builder copied
only six provider headers into the Synology kernel tree. That candidate and
an earlier EPYC7002 rebuild that Oopsed imported the same 124 DRM symbols,
including `drm_gem_handle_delete` and `drm_master_get`.

For the successful r1000nk pilot, NVIDIA's `conftest` and Kbuild saw the
matching provider's full `include/drm` and `include/uapi/drm` trees, the
matching `iosys-map.h`, and four DMA-fence/reservation headers. The build
retained the pinned symbol-alias shim, matching provider `Module.symvers`,
`CONFIG_DRM_MODULE=1`, and `NO_BACKLIGHT=1`. The optional
`NV_DRM_IOSYS_COMPAT=1` hook in `build-nvidia.sh` adds the provider's
`iosys_map` definition to the extracted NVIDIA GEM source; it is off by
default for other builds. The provider's `nomodeset.h` wrapper was supplied
through the backport include path with
`BPM_VGACON_TEXT_FORCE_NOT_PRESENT`, not copied into the kernel tree.

The revised module imported 129 DRM symbols. Compared with the physically
successful EPYC7002 reference (132), only three were absent:
`drm_aperture_remove_conflicting_framebuffers`,
`drm_aperture_remove_conflicting_pci_framebuffers`, and
`drm_atomic_helper_shutdown`. It introduced no DRM imports absent from that
reference, and no longer imported the two old-path names above. All its DRM
imports resolved against the released r1000nk DRM pack. These static checks
were useful gates; they did not by themselves prove runtime safety. The
physical loading result supplied that separate confirmation.

The evidence points to a mismatched DRM header/API selection in the earlier
build. It does **not** establish a single-line root cause: multiple header
and include-path adjustments were needed, and the successful EPYC7002
attempt-6 build did not preserve its complete flags. Both the EPYC7002
success and r1000nk failure used a symbol-alias shim, so shim presence alone
was not the deciding difference.

## Rebuild and validation

The locally repeatable pilot procedure is
`scripts/kms-compat/580.173.02/build-r1000nk-kms-pilot.sh`. It requires the
matching r1000nk provider source/build/`Module.symvers`, the released
r1000nk DRM pack for import checking, and the canonical EPYC7002 reference
already staged at the explicit `out/` paths in the script. These inputs are
local build evidence and are **not** committed; a fresh clone must prepare
them before running the script. Do not substitute a provider from another
platform or DSM/kernel build.

Run inside the pinned compiler image, mounting this repository at `/work`:

```sh
docker run --rm --privileged -u 0 --entrypoint bash \
  -v "$PWD:/work" \
  'dante90/syno-compiler:7.4@sha256:08cedce8be257c7b3f2b32c8edde034cc53754f0bad1f974b63c76607d7eab1f' \
  /work/scripts/kms-compat/580.173.02/build-r1000nk-kms-pilot.sh
```

The script refuses to overwrite its output archive. For a repeat attempt,
pass a new container path using, for example,
`docker run -e OUT_DIR=/work/out/r1000nk-kms-repeat-01 ...`. It checks the
non-stub DRM module,
vermagic, `modeset` parameter, provider symbol resolution, and absence of
the prior old-path DRM imports. Before another device load, verify the
archive and GSP checksums, confirm a clean target boot and exact platform,
then load the existing DRM provider, `nvidia.ko`, `nvidia-modeset.ko`, and
finally `nvidia-drm.ko modeset=1`. Stop immediately if the kernel reports an
Oops; do not continue probing a tainted boot.
