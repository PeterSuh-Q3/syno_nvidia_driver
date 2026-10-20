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

## K5 DRM provider build prerequisites

- After any context compaction, handoff, or resumed turn in a long KMS build,
  reread this section and the applicable version ledger
  (`docs/595-open-kms-build-progress.md` or `docs/580-open-kms-build.md`)
  before taking another build action. Treat that ledger as the current
  evidence-based state; do not rely on recollection or a partial conversation
  summary alone. Update the ledger immediately after each platform's provider
  build, candidate validation, and runtime test.
- The pinned `dante90/syno-compiler:7.4` image does not include `flex`/`lex`
  or `bison`, which the dual-DRM provider's `defconfig-drm` step needs. Before
  any fresh disposable provider-build container runs, install and record the
  pinned Debian packages `flex=2.6.4-8.2` and `bison=2:3.8.2+dfsg-1+b1`.
  Provider preparation scripts must fail early if either exact version is
  missing. Never assume packages installed in a previous `docker run --rm`
  remain available in the next container.
- This omission caused the same avoidable failure in both the 595 Open
  EPYC7002 and EPYC7003 provider-preparation attempts. Check this rule before
  starting each new provider build; record the package versions in its build
  evidence.
- Use one fresh disposable compiler container per platform. The provider
  workflow uses fixed `/tmp/drm` paths, so a multi-platform loop inside one
  container can collide with residue from the previous platform. Before each
  platform, verify the exact compiler-image digest, install and assert both
  pinned packages, then run only that platform's provider preparation and
  NVIDIA build. Do not reuse an earlier container's package installation or
  temporary build tree.
- Provider build output must be located from the actual workflow output path
  before packaging/copying it; do not assume an `OUT_MODULES` override was
  honored. Confirm every required `.ko` exists and is non-empty, and preserve
  the provider config, `Module.symvers`, build log, package versions, and
  checksums in the receipt.
- Preserve the compatibility-shim distinction: `geminilakenk` uses its
  platform-specific provider-header/API compatibility path and must not inherit
  the focused3 DMA-BUF alias shim by default. The other five platforms use
  their own evidence-driven shim/build path; never flatten these into one
  generic shim recipe. Inspect imports and validate against that platform's
  exact provider ABI before accepting a candidate.
- The 580 Open six-platform KMS host runner executes platforms in this fixed
  order: `epyc7002`, `epyc7003`, `icelaked`, `r1000nk`, `v1000nk`, and
  `geminilakenk` last. It starts a new pinned disposable compiler container
  for each platform and writes candidates only under `out/kms-expansion/`.

## NVIDIA driver package descriptions

- For K5 NVIDIA driver SPKs, do not mention `DSM 7.2` (or another DSM minimum)
  in the user-visible package description. Keep the compatibility metadata such
  as `os_min_ver` unchanged unless the requested compatibility range itself is
  being changed.
- The package description should still identify the driver flavor/version,
  CUDA API version, supported GPU range, kernel version, and bundled platforms.
