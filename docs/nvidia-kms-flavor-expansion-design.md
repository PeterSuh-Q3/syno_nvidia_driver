# K5 NVIDIA KMS build expansion plan

## Goal and scope

Extend the KMS-capable NVIDIA module build method proven for 580 Proprietary to
these three independent K5 profiles:

| Profile | Driver | Flavor | Platforms |
| --- | --- | --- | --- |
| `kver5-580-open` | 580.173.02 | open | epyc7002, epyc7003, geminilakenk, icelaked, r1000nk, v1000nk |
| `kver5-595-open` | 595.99.02 | open | same six supported K5 platforms |
| `kver5-595-proprietary` | 595.99.02 | proprietary | same six supported K5 platforms |

The goal is to build and validate `nvidia-drm.ko` with its `modeset=1` path,
then promote a complete profile as a unit. A successful compile or presence of
the `modeset` parameter is not proof of runtime KMS support.

## Evidence and current baseline status

The 580 Proprietary method is not one universal shim recipe. Use the exact-
platform provider headers and `Module.symvers` where the selected build needs
the provider ABI, and select compatibility shims based on that platform's
actual conftest/build inputs and resulting imports. The successful EPYC7002
`focused3-shim` build is one reference, not a blanket instruction to inject
that alias shim into every platform or driver version. Do not substitute a
provider or kernel input from a different platform. Do not load a provider
pack merely because the build used its headers: on the confirmed EPYC7002
runtime test, the additional provider pack was not needed for the successful
module load.

### Shim taxonomy and platform evidence

“Shim” refers to distinct compatibility mechanisms in this work; they are not
interchangeable:

| Mechanism | What it adapts | Evidence / applicability |
| --- | --- | --- |
| Provider-header ABI inputs (`drm-include`, `i915-include`, matching `Module.symvers`) | Makes NVIDIA conftest/Kbuild see the same DRM declarations and exported-symbol ABI as the selected provider build. These are build inputs, not themselves a shim. | Must match the exact platform, DSM release, and kernel. Never borrow another platform's headers or symbol table. |
| `video/nomodeset.h` compatibility wrapper | Bridges the provider backport's `nomodeset` header/API into NVIDIA's build. | Recorded for the 580 Gemini Lake provider-header pilot in `docs/geminilake-nvidia-drm-abi.md`; this does not imply use of the focused3 DMA-BUF alias shim. |
| `drm-provider-symbol-aliases.h` (“focused3” DMA-BUF alias shim) | Maps NVIDIA's `LINUX_DMABUF_BACKPORT(...)` references to the provider's `dmabufbkpt_*` exports. | Used by the physically KMS-tested 580 EPYC7002 focused3 path and by the 580 r1000nk successful pilot. Apply only when the target build's source/conftest and imports call for it; shim presence alone does not establish compatibility. |

The final 580 Proprietary SPK's Gemini Lake `nvidia-drm.ko` matches the
recorded provider-header pilot artifact. Its undefined-symbol table contains
no `dmabufbkpt_*` reference, so the focused3 DMA-BUF alias shim is not
evidenced as part of that Gemini artifact. The Gemini pilot record does
document the provider-header inputs and `video/nomodeset.h` wrapper, but marks
that artifact as compile-time/symbol-check evidence rather than a captured
runtime certification. Keep those evidence levels distinct.

For 595 Proprietary, the KMS pilot script pins the focused3 alias shim and
supports optional exact-platform provider-source headers. However, the
Gemini Lake archive in the current 595 Proprietary candidate set is byte-for-
byte identical to the pre-promotion archive; there is no Gemini Lake run
directory/receipt showing that the 595 pilot recipe was executed for it. Its
lack of `dmabufbkpt_*` imports therefore does not prove that the shim is
unnecessary for a newly built 595 Gemini module. Rebuild Gemini separately
with its matching provider inputs, inspect the generated imports to decide
whether the alias shim is needed, then perform runtime KMS validation before
promoting it.

The current canonical 580 Proprietary module assets have already been promoted
to the KMS-enabled set. The repository does not currently establish that the
complete original no-KMS six-platform set was retained byte-for-byte. A normal
580 Proprietary build profile exists, and there is a partial EPYC7003
reproduction baseline under ignored `out/`, but neither fact proves that the
original six-pack no-KMS baseline is recoverable. Do not label a rebuilt
baseline as the historical one. If an exact original artifact cannot be
located and hash-verified before any future replacement, record it as
unavailable and use the current published/release asset as the rollback
baseline.

The three target profiles currently have regular module archives under
`out/release-assets-nvidia/`; preserve each archive and its SHA-256 before
building as the pre-change baseline. Confirm each profile's actual no-KMS
status from its module/runtime configuration before labeling it “no-KMS”; the
mere presence of a `modeset` module parameter does not establish whether the
SPK enables it. Treat the existing canonical shared userspace and GSP bundles
as immutable shared inputs; do not regenerate or copy them into per-platform
or per-candidate directories. Follow `AGENTS.md` and verify the shared-layer
invariant with `scripts/check-shared-nvidia-layers.sh`.

## Isolation and promotion model

For each profile, keep two explicit states:

1. **Baseline (no KMS):** immutable archive set plus a receipt containing the
   profile, six platform filenames, SHA-256 values, source revision, and
   whether each artifact's `nvidia-drm.ko` exposes `modeset`.
2. **KMS candidate:** a new, unique output directory. Never build over the
   baseline or directly into `out/release-assets-nvidia/`.

Use a version/flavor-scoped layout, for example:

```text
out/kms-expansion/<profile>/<build-id>/
  artifacts/      # candidate nv-ko archives; no shared userspace/GSP copies
  logs/           # per-platform full build logs
  evidence/       # extracted module metadata, ABI/import reports, test records
  BUILD-RECEIPT.json
  SHA256SUMS
```

The build script for each profile must be fail-closed, pin the compiler image
and `.run` checksum, accept no implicit profile/flavor/platform substitution,
refuse existing output paths, and record all inputs and hashes. Build the six
platforms as a candidate set; a partial build never changes canonical assets.
KMS recipes modify kernel-build headers/configuration while preparing
`conftest` and Kbuild. Therefore each profile/platform candidate must start
from a clean, exact matching toolchain kernel tree (fresh disposable compiler
container or a verified pristine copy); never let headers or generated config
from one KMS candidate leak into another candidate or the no-KMS build.

Promotion is an explicit second operation, after all six platform candidates
pass build-time checks and device validation. First retain a verifiable copy
of the exact no-KMS baseline. Then replace only that profile's six module
archives in the local canonical asset directory, compare the promoted hashes
with the candidate receipt, and rebuild the corresponding SPK only after its
installer behavior has been reviewed. Release publication/cache updates are
separate actions and are not part of this design phase.

## Build and validation sequence

### Repeated build-prerequisite failure and prevention (2026-10-20)

The base pinned compiler image lacks `flex`/`lex` and `bison`. The provider
`defconfig-drm` step fails before compilation if they are absent. This was
missed twice: first during the 595 Open EPYC7002 provider-input preparation,
then again during EPYC7003 preparation, even though the first occurrence had
already been recorded in the working handoff. This was an execution oversight,
not a source or ABI failure. New disposable containers do not inherit packages
installed in earlier `docker run --rm` invocations.

Before provider preparation, install and record the pinned packages
`flex=2.6.4-8.2` and `bison=2:3.8.2+dfsg-1+b1`. The platform-preparation script
must assert these versions before invoking the workflow. The Open expansion
runner installs them afresh in one disposable container per platform and
records versions under
`out/kms-expansion/kver5-595-open/dependencies/<platform>-<run-id>.txt`.
The provider workflow uses a fixed `/tmp/drm` path, so do not loop through
platforms inside one container. Validate modules from the workflow's actual
`source/out/modules` output directory rather than assuming the `OUT_MODULES`
override controls the final module copy.

1. **Inventory and freeze:** record current baseline hashes for all 18 target
   module archives, shared userspace/GSP hashes, `.run` hashes, source commit,
   current package IDs/revisions, and relevant build settings. Confirm the
   three target regular packs' no-KMS state before calling them that. Keep the
   immutable baseline outside candidate output directories.
2. **Pilot each profile independently:** start with `epyc7002` for each of the
   three targets, because that is the platform with the strongest known
   580 Proprietary reference. The 580 Proprietary flags/shim are a recipe to
   investigate, not a blind patch to apply to different driver versions or
   flavors. Each pilot must run that target's own `conftest` and Kbuild using
   matching provider inputs.
3. **Static candidate checks:** for every platform verify real (non-stub)
   modules, expected platform/version/flavor, `5.10.55+` vermagic, presence of
   `nvidia-drm.ko` and its `modeset` parameter, required module set, and
   resolution of imported DRM symbols against the exact matching provider
   `Module.symvers`/provider pack. Compare DRM imports with an accepted
   physically successful reference; reject unexplained new imports and known
   obsolete API imports. Static checks only permit the next test; they do not
   qualify a release.
4. **Physical load tests:** use a clean and identified target platform. Load
   the intended dependency set in controlled order, then NVIDIA core,
   modeset, and `nvidia-drm` with `modeset=1`. Verify command exit status,
   `modeset` runtime value, kernel log (`Initialized nvidia-drm` and no
   Oops/warnings indicating ABI failure), GPU-to-DRM association, and expected
   `/dev/dri` nodes. Stop immediately on Oops or unexplained instability.
5. **Application regression tests:** verify `nvidia-smi`, Docker runtime GPU
   access, and at least the affected host media-transcoding path (Plex and/or
   Jellyfin where installed). Record whether GPU discovery and hardware
   encode/decode still work after package startup and reboot. This is required
   because KMS node creation alone does not prove CUDA/ NVENC/NVDEC behavior.
6. **Profile promotion decision:** promote only if all six platform builds
   pass static gates and each platform has a physical KMS validation result,
   with application regression checks on representative device(s). Otherwise
   retain the full no-KMS baseline and leave the candidate isolated. If KMS
   causes a material regression, do not replace the stable package assets;
   consider a separately identified experimental package only after a
   separate design decision.

## Runtime/package behavior

KMS is enabled at module load (`nvidia-drm modeset=1`); building a module that
merely contains the `modeset` parameter is insufficient. The SPK must only
advertise/enable this path when its full module set has been promoted and its
installer/startup logic is verified to load it. For each target SPK, check
whether a matching DRM provider bundle is required for unresolved symbols and
package dependency closure; never infer this from the flavor name. Keep the
provider-pack question separate from KMS mode: the successful EPYC7002 test
showed a provider pack was not required at runtime for that tested module,
while the 580 Proprietary package currently bundles matching provider packs.

Do not silently change package IDs or package revisions during candidate
builds. Before promotion, review whether the current package installation,
startup, migration, and rollback semantics can safely replace the module set.
If the safe rollback requires preserving the no-KMS user-visible package,
stop before release promotion and decide whether the KMS variant needs a
distinct package ID.

## Deliverables for the implementation phase

- Three locked profile builders or one explicitly parameterized builder with
  strict per-profile allowlists and pinned inputs.
- Per-platform artifact validation and a build receipt with input/output
  hashes.
- A separate, non-destructive promotion script that verifies the receipt and
  baseline snapshot before replacing any canonical archive.
- A validation matrix recording static checks, physical KMS results, and
  application regression results for each profile/platform.
- No release asset, package catalog, cache server, or package revision change
  until the user explicitly requests publication after candidate acceptance.
