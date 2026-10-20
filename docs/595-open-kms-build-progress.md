# NVIDIA 595 Open KMS build progress

This is the handoff ledger for the current 595.99.02 Open KMS expansion. Keep
it updated after every provider build and candidate validation so context
compaction cannot erase which method was used or what remains unverified.

Current checkpoint: five remaining platform candidate archives now exist and
all passed static module/provider-symbol validation. The first Gemini pass was
rejected by an incorrect generic required-module check; after correcting the
Gemini `drm_mipi_dsi.ko` exception, its fresh-container retry passed. None of
the five has been physically KMS-tested or promoted. The host wrapper's first
full-pass exit status remains nonzero because it recorded that first Gemini
validation failure; the successful retry is a separate recorded run.

## Fixed invariants

- DSM 7.4, kernel 5.10.55, pinned compiler image
  `dante90/syno-compiler:7.4@sha256:08cedce8be257c7b3f2b32c8edde034cc53754f0bad1f974b63c76607d7eab1f`.
- One fresh disposable Docker container per platform. The provider workflow
  claims the fixed `/tmp/drm` path; never build multiple platforms in one
  container.
- Install and verify `flex=2.6.4-8.2` and `bison=2:3.8.2+dfsg-1+b1` inside
  every fresh container before provider preparation. Keep the per-platform
  dependency receipt, provider receipt, build log, module ABI evidence, and
  candidate receipt.
- Use the matching `mshell-modules` 26.10.15 quad-DRM provider asset, source
  commit `a89571ecf197c83c04e16b1f09c516732defe91e`, and exact platform DSM
  kernel `.config`/`Module.symvers`/toolchain. The provider workflow's actual
  module output is `source/out/modules`; do not infer a different location
  from `OUT_MODULES`.
- The Gemini compatibility path is distinct: provider-header/API overlay,
  without focused3 DMA-BUF alias shim by default. The other platforms use the
  focused3 DMA-BUF alias shim, subject to exact-provider ABI validation.
- These are candidate builds only. No candidate is promoted or considered
  runtime KMS-tested until tested on the corresponding physical platform.

## Platform ledger

| Platform | Provider inputs | NVIDIA candidate | Static validation | Physical KMS test | Status |
| --- | --- | --- | --- | --- | --- |
| epyc7002 | Built earlier; exact provider inputs retained under `out/kms-expansion/inputs/epyc7002-26.10.15-provider-build` | `out/kms-expansion/kver5-595-open/epyc7002-20261020T115811Z/artifacts/nv-ko-595.99.02-open-epyc7002-51055.tgz` | Passed; SHA256 `a6ba75b84d9513d49b51c051bc890b8061d33c42f8149a5dd7ced307404149ee` | Pending | Candidate only |
| epyc7003 | Built successfully from 26.10.15 exact-platform source/provider ABI under `out/kms-expansion/inputs/epyc7003-26.10.15-provider-build`; dependency receipt `out/kms-expansion/kver5-595-open/dependencies/epyc7003-20261020T133448Z.txt` | `out/kms-expansion/kver5-595-open/epyc7003-20261020T133448Z/artifacts/nv-ko-595.99.02-open-epyc7003-51055.tgz` | Passed; SHA256 `5d638e65431f3dcc3464c068a6e08cee1f72ba1e37410538e71fcacc5217e3ec`; exact provider DRM imports resolve | Pending | Candidate only |
| geminilakenk | Provider DRM closure completed under `out/kms-expansion/inputs/geminilakenk-26.10.15-provider-build`; exact workflow omission of `drm_mipi_dsi.ko` respected. Retry dependency receipt: `out/kms-expansion/kver5-595-open/dependencies/geminilakenk-20261020T135625Z.txt` | `out/kms-expansion/kver5-595-open/geminilakenk-20261020T135625Z/artifacts/nv-ko-595.99.02-open-geminilakenk-51055.tgz` | Passed; SHA256 `8b7c54bdbcb4cfa36fb3b230c3a24862605048e7c72c2af660f051a188b00e6e`; exact provider DRM imports resolve; Gemini-specific export adjustments retained; no focused3 alias shim | Pending | Candidate only |
| icelaked | Provider DRM closure completed under `out/kms-expansion/inputs/icelaked-26.10.15-provider-build` | `out/kms-expansion/kver5-595-open/icelaked-20261020T134215Z/artifacts/nv-ko-595.99.02-open-icelaked-51055.tgz` | Passed; SHA256 `9b5a2ff990007f3a95c3dcc4a5729751284d3e2514c46e5e529c90a927fafef3`; exact provider DRM imports resolve | Pending | Candidate only |
| r1000nk | Provider DRM closure completed under `out/kms-expansion/inputs/r1000nk-26.10.15-provider-build`; matching backport dependency config and i2c-algo-bit provider built | `out/kms-expansion/kver5-595-open/r1000nk-20261020T134704Z/artifacts/nv-ko-595.99.02-open-r1000nk-51055.tgz` | Passed; SHA256 `88268742509cc8017699456d767649da100a0e64532f2556dc51bba83cff327e`; exact provider DRM imports resolve | Pending | Candidate only |
| v1000nk | Provider DRM closure completed under `out/kms-expansion/inputs/v1000nk-26.10.15-provider-build`; matching backport dependency config and i2c-algo-bit provider built | `out/kms-expansion/kver5-595-open/v1000nk-20261020T135124Z/artifacts/nv-ko-595.99.02-open-v1000nk-51055.tgz` | Passed; SHA256 `36a4d1ae97069d2b404ced758cbf9e11a7b7f16f070feb7b75c97ccbbe08280e`; exact provider DRM imports resolve | Pending | Candidate only |

## Repeated mistake acknowledged

The flex/bison prerequisite was already encountered on EPYC7002 but was
forgotten operationally on EPYC7003. That was not an ABI failure and should
not be described as context loss alone: the fact was present in the handoff,
but the preflight was not enforced. A prior attempt also reused a container,
causing `/tmp/drm` collisions, and the provider verifier checked the wrong
module-output directory. The host runner and one-platform container runner
were changed to enforce fresh containers and per-run prerequisite receipts;
the provider verifier now checks `source/out/modules`.
