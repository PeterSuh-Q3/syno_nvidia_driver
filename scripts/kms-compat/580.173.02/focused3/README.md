# NVIDIA 580.173.02 KMS focused3 build inputs

This directory pins the inputs for the controlled **focused3 diagnostic**
build performed on 2026-10-16. It supports repeat compilation for `epyc7002`
and `epyc7003` with the same six selected provider headers and a
platform-matched provider `Module.symvers` file.

The NVIDIA shim is `drm-provider-symbol-aliases.h`; it is force-included into
NVIDIA's kernel-module compilation. The six headers are overlaid onto the
matching platform tree inside a disposable, digest-pinned compiler container.
The script also enables `CONFIG_DRM_MODULE=1` only in that disposable image
layer and sets `NO_BACKLIGHT=1` and `JOBS=12`.

## Provenance and licensing

The six Linux DRM/DMA-BUF headers are copied unchanged from
`PeterSuh-Q3/dual-gpu-backports`, commit
`da5c5a98afc46ecdbc27fc0631cc7bb5c6736f08`, under their individual
`SPDX-License-Identifier: GPL-2.0-only` notices. The GPL text is preserved at
the repository's `LICENSES/GPL-2.0.txt`. The rest of this repository's license
does not replace the headers' original license.

The two provider symbol tables were generated from matching platform builds:

- `epyc7002/provider-Module.symvers` — diagnostic provider build input,
  SHA-256 `03db04a462c75755e62d63f3bdc775599697080d9694e738f240666c3475f5c0`.
- `epyc7003/provider-Module.symvers` — provider build at the `da5` source
  snapshot, SHA-256 `dabea5f2d5a7549f604027e9f06ff9aa38734d8694dae7d410f72246c983ab78`.

These scripts produce diagnostic artifacts for inspection. In particular,
the EPYC7002 focused3 output is **not** byte-identical to the historical
attempt-6 canonical success pack, and the EPYC7003 result has not been
runtime-tested on an EPYC7003 device. The workflow never updates release assets.
