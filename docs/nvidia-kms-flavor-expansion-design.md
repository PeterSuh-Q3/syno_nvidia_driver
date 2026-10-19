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

The 580 Proprietary method to reproduce is the full-header, exact-platform
recipe documented in `docs/nvidia-580-r1000nk-kms-pilot-succ.md` and
`docs/nvidia-580-remaining-kms-build-candidates.md`, with the successful
EPYC7002 `focused3-shim` procedure as the reference. It uses the platform's
matching DRM provider headers and `Module.symvers`, the pinned alias shim,
matching Kbuild/conftest inputs, and validates the resulting module against
that platform's provider. Do not substitute a provider or kernel input from a
different platform. Do not load a provider pack merely because the build used
its headers: on the confirmed EPYC7002 runtime test, the additional provider
pack was not needed for the successful module load.

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
