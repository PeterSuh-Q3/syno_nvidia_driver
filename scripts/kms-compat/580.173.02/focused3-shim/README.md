# NVIDIA 580.173.02 EPYC7002 focused3-shim — confirmed KMS success

## Confirmed result

This is the successful **EPYC7002-only** 580 Proprietary KMS path confirmed on
physical test device `45.5` (SA6400, DSM 7.4, kernel `5.10.55+`) on
2026-10-16. The tested NVIDIA module pack loaded with `nvidia-drm modeset=1`;
the kernel reported `Initialized nvidia-drm`, DRM device nodes appeared, and
the Junior helper reported normally.

No separate DRM-provider module pack was loaded or required for this result.
The NVIDIA module build did use the symbol-alias shim pinned in this
directory. “No provider pack” must not be read as “no shim.”

## Tested artifact and source identity

- Kernel archive: `nv-ko-580.173.02-proprietary-epyc7002-51055.tgz`
- Archive SHA-256: `df457fbb6559938afcfc8816ebe06c56d0e8b1a53e920a9dce54dcc1346884a4`
- Extracted `nvidia-drm.ko` SHA-256:
  `45e48b2c4bd66a4d5a6eb047b46e4f782ca1ba5a934bd0f7be662c15b1777380`
- Module exposes the `modeset` parameter.
- NVIDIA 580.173.02 `.run` SHA-256:
  `8d8eb9001e05a9a8a663d3d5d304feb64ef2844ee185ccdfd952786820f46e1b`
- Compiler image:
  `dante90/syno-compiler:7.4@sha256:08cedce8be257c7b3f2b32c8edde034cc53754f0bad1f974b63c76607d7eab1f`
- Build-script baseline: commit `41de1cbbabfa5e141c77ba488fb7353cd5c5626b`,
  `build-nvidia.sh` blob `3f0e72297d4af83f7b3b90cb48973f4a62c6c41a`.
- Tested archive is byte-identical to the EPYC7002 580 Proprietary kernel
  archive in `out/release-assets-nvidia/kver5-580-proprietary/`.

The original successful shim is preserved here as
`drm-provider-symbol-aliases.h` (SHA-256
`a04daa03b8059439b2397ef31cd3a2a4e5b1563493b6519a9807669f3ab38ff9`). Its
hash is pinned so a later edit cannot silently substitute another shim.

## Exact scope and reproducibility boundary

This hardware result confirms the EPYC7002 path only. It neither confirms nor
invalidates other platforms' KMS status. Four additional platforms are planned
for individual physical-device validation.

The attempt-6 build log and platform inputs are preserved locally under
`out/preserved-build-envs/580-proprietary-kms/epyc7002-canonical-success/`.
The log confirms `NO_BACKLIGHT=1`, successful module linking, the output hash,
and reuse of the shared userspace layer. It does **not** record the complete
`EXTRA_CFLAGS` / `KBUILD_EXTRA_SYMBOLS` invocation or job count. Therefore this
directory pins the known-success source shim and artifact provenance, but the
full command is not yet claimed as byte-for-byte reproducible. The removed
provider-overlay diagnostic recipe was not the EPYC7002 success recipe.

## Failed provider experiment — not retained as a build path

A separate provider-header experiment produced an EPYC7002 archive with SHA-256
`1ca841a8827c887bae4686bcff7a5217d5e4bc37a81d1f5b5c686f1acaafc04d`. Loading
that archive caused a kernel Oops during DRM registration and did not produce
the expected DRM nodes. Its source overlays, provider symbol tables, launcher,
validator, and workflow have been removed from the working build paths. The
failed archive and logs remain only in local `out/` diagnostics and are not
canonical or safe-to-load artifacts.
