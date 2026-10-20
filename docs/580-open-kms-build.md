# NVIDIA 580 Open KMS: six-platform candidate build

## Purpose and guardrails

This recipe prepares KMS-enabled `580.173.02` Open kernel-module candidates
for the six supported K5 platforms. It follows the successful 580 Proprietary
full-header/provider-ABI method and the later 595 Open execution safeguards.
It does **not** change canonical Open module packs, build an SPK, publish a
release, or claim physical KMS validation. Results stay under
`out/kms-expansion/kver5-580-open/` until separately reviewed and tested.

The host runner is
`scripts/kms-compat/580.173.02/build-open-six-platforms.sh`. It uses this
fixed order, with the platform-specific Gemini path deliberately last:

1. `epyc7002`
2. `epyc7003`
3. `icelaked`
4. `r1000nk`
5. `v1000nk`
6. `geminilakenk`

Each platform runs in its own disposable
`dante90/syno-compiler:7.4` container pinned to the image digest recorded in
the scripts. Do not combine platforms in one container: the provider workflow
uses fixed `/tmp/drm` paths, and KMS builds overlay kernel headers/config.
Each container installs and records `flex=2.6.4-8.2` and
`bison=2:3.8.2+dfsg-1+b1`.

## Required local inputs

The exact DSM 7.4 / kernel 5.10.55 cross-toolchains are supplied by the pinned
image. Before execution, these inputs must exist and match the recorded
receipts:

- `run/NVIDIA-Linux-x86_64-580.173.02.run` (SHA-256 pinned in the builder).
- Shared `out/release-assets-nvidia/shared/580/nv-userspace-580.173.02.tgz`
  and `nv-gsp-580.173.02.tgz`; these remain single shared files and are never
  copied into platform build output.
- The six current Open baseline archives under
  `out/release-assets-nvidia/kver5-580-open/`. The builder copies each exact
  baseline into its candidate evidence before compiling and never overwrites
  these files.
- Exact platform provider evidence at
  `out/kms-expansion/inputs/<platform>-26.10.15-provider-build/`, including
  provider headers, `provider-Module.symvers`, modules, config, and
  `PROVIDER-RECEIPT.txt`; matching provider packs at
  `work/shared-quad-drm-providers/<platform>-7.4-5.10.55-drm.tgz`. Source
  commit and provider-pack checksums are checked against the receipt. These
  generated inputs are local `out/` evidence, not committed artifacts.
If a provider receipt, exact platform pack, or shared input is absent, stop
and prepare/restore that exact input first. Never substitute another
platform's provider or a different DSM/kernel family.

The baseline archive hashes verified when this recipe was prepared are:

| Platform | Current Open baseline SHA-256 |
| --- | --- |
| epyc7002 | `d748835c560fcab11e645688c7f585aafd945843141720ee91844e24a8db3292` |
| epyc7003 | `6ac75e26afc7624f98af249924919aa22693609967deb28ce1ff153e6c48549b` |
| icelaked | `5688d4b29535cbb59ce9e911e3cec9024a3c349baec49e7c36443c2dcc5110e1` |
| r1000nk | `2e9c574505d9965531610f2e9fa132d5191a75d5bdb0264208c183756dc45f93` |
| v1000nk | `5374008faafebcc6fa73088250048c151af652da18186f7a92319251b8fcadcd` |
| geminilakenk | `b1e50c66f36775db7edf119a422b1cfc70e9f02fd0d2bdbd31f141356d562113` |

Shared-layer hashes at preparation time: userspace
`362d89477c7217927c17e71f0209c51a3a349756f195633b61ede2905844be79`, GSP
`39f99970299a398f82b7c6d61a20f22faca1589b044822bdf1e5a36094c7d62b`.

## Preparation checkpoint (2026-10-20)

| Platform | Exact provider pack hash checked | Candidate build | Physical KMS test | Promotion |
| --- | --- | --- | --- | --- |
| epyc7002 | `1e2485c6c5e963c7f392781c5375b3cb8374f0bd8541b7c0fab866b5434dd64c` | Passed static checks; `out/kms-expansion/kver5-580-open/epyc7002-20261020T140944Z/artifacts/nv-ko-580.173.02-open-epyc7002-51055.tgz`; SHA-256 `193b75c0ee20a3dc86967a165336b6d8a1fe1519bde6a8b8543d6515db6e3e49` | Pending | Not promoted |
| epyc7003 | `86f3676a0269faf73439f3cb4afb9979def9f64ba7292769fd43463634309910` | Passed static checks; `out/kms-expansion/kver5-580-open/epyc7003-20261020T141119Z/artifacts/nv-ko-580.173.02-open-epyc7003-51055.tgz`; SHA-256 `4eec471d93dfed950e56ea4e390a6ff115cd8806439443f4186727832fe0f451` | Pending | Not promoted |
| icelaked | `0e673b94ebea05442163a4ce1c49a96f2aadb0be8be2d4f608b8a8fc7adb53d9` | Passed static checks; `out/kms-expansion/kver5-580-open/icelaked-20261020T141250Z/artifacts/nv-ko-580.173.02-open-icelaked-51055.tgz`; SHA-256 `dd4c765cb3f4ebe23e6b289007d617f2a7988690f4e95d26110e54de83be8f26` | Pending | Not promoted |
| r1000nk | `da8bd4d3fa08acd46f1a0c4632ed3cd68807a528742c2b2160fc0743334e8e68` | Passed static checks; `out/kms-expansion/kver5-580-open/r1000nk-20261020T141421Z/artifacts/nv-ko-580.173.02-open-r1000nk-51055.tgz`; SHA-256 `87a1384232d65b2fff2255c2d5fada17cc1f26c6748483b09392fc5c6e757da2` | Pending | Not promoted |
| v1000nk | `f8306467031a58bf2c06cbb55bae6ccb47c8295380c638bf52fb163b2c28ac65` | Passed static checks; `out/kms-expansion/kver5-580-open/v1000nk-20261020T141551Z/artifacts/nv-ko-580.173.02-open-v1000nk-51055.tgz`; SHA-256 `6ab38aad4cee54a5bff4835489fff3558527a140ba43842d0384d4374af6fa01` | Pending | Not promoted |
| geminilakenk | `542621fbb5d731dedde7fe108e7e058ead28e04252e1a8ba6043583c7f3ac4fc` | Passed static checks; intentionally last; `out/kms-expansion/kver5-580-open/geminilakenk-20261020T141716Z/artifacts/nv-ko-580.173.02-open-geminilakenk-51055.tgz`; SHA-256 `85e6c168014c6b7e1b65fcb6eb28d5f36ee86259ae906322a5ceb7fc3b318277` | Pending | Not promoted |

All six baseline archives, provider receipts/modules/headers/symbol tables,
shared userspace/GSP files, and the pinned `.run` were present at this
checkpoint. The scripts pass `bash -n` and ShellCheck. All six candidates
passed the build and static ABI gates in the prescribed
order, with `geminilakenk` last. Physical KMS load tests are pending for all
platforms. No candidate has been promoted.

## Run

From the repository root on the build host:

```sh
bash scripts/kms-compat/580.173.02/build-open-six-platforms.sh
```

The runner creates one timestamped candidate directory per platform and one
dependency receipt per fresh container. It continues through all six
platforms to preserve successful candidates if one fails, but exits nonzero
if any platform fails. Inspect that platform's log under
`out/build-logs/580-open-platforms/` and its candidate evidence before retrying;
never overwrite an existing candidate directory.

## Compatibility and validation rules

- Each candidate builds from `kernel-open` and uses matching provider
  DRM/UAPI headers, `iosys-map.h`, DMA-fence/reservation headers, and provider
  `Module.symvers`. `NV_DRM_IOSYS_COMPAT=1`, 12 build jobs, and the pinned
  focused3 DMA-BUF alias shim apply only to the five non-Gemini platforms.
- `geminilakenk` is last and uses its platform-specific provider-header/API
  compatibility path without the focused3 alias shim. Its `NO_BACKLIGHT`
  setting is kept distinct from the other five platforms.
- Static acceptance checks the real module set (not stubs), platform/version
  markers, `5.10.55+` vermagic, `modeset` parameter, and DRM imports against
  both the exact released provider pack and exact provider-build exports.
- Candidate and baseline hashes, shared layer hashes, `.run` hash, provider
  receipt, kernel config/symbol table, shim identity, and runtime/promotion
  status are retained under that platform's candidate directory.
- Static success is only a build gate, not proof that `modeset=1` loads safely.
  Test each corresponding physical platform in a clean state, inspect kernel
  logs for Oops/ABI faults, and verify NVIDIA DRM nodes before promotion. Do
  not replace stable no-KMS packs until all validation and a separate
  promotion decision are complete.

After a long pause or context compaction, reread this document and
`AGENTS.md` before resuming. Record each candidate path/hash, static result,
physical test result, and promotion state here as work proceeds.
