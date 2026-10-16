# NVIDIA 580 Proprietary KMS — three additional platform validations

On 2026-10-16, `epyc7003`, `icelaked`, and `v1000nk` were rebuilt for DSM 7.4,
kernel 5.10.55+ with the pinned `dante90/syno-compiler:7.4` image and 12 jobs
per platform. The build method follows
`docs/nvidia-580-r1000nk-kms-pilot-succ.md`: each NVIDIA conftest and Kbuild
uses that platform's matching DRM/UAPI provider headers, `iosys_map`, symbol
alias shim, and provider `Module.symvers`. The earlier six-header-only recipe
was not used.

| Platform | Candidate archive | SHA-256 |
| --- | --- | --- |
| epyc7003 | `out/kms-580-proprietary-fullheaders-20261016/epyc7003/nv-ko-580.173.02-proprietary-epyc7003-51055.tgz` | `44fd42f59c1ad8e940a9c859ba4b0e4fbd65e179bdb13ac0e1a7ce047d51ce7a` |
| icelaked | `out/kms-580-proprietary-fullheaders-20261016/icelaked/nv-ko-580.173.02-proprietary-icelaked-51055.tgz` | `dc6d505aa16f6bda2c61f78af0ea3319a1556cfd3fbaaa8b05d26fab895b0d3c` |
| v1000nk | `out/kms-580-proprietary-fullheaders-20261016/v1000nk/nv-ko-580.173.02-proprietary-v1000nk-51055.tgz` | `6a1cc6ed5c30a8b738aefa1b010f6916b9e7bb4dfcf990bee7cb0f9f49f46d0b` |

Each pack contains five real `.ko` modules, has the correct `PLATFORM`
and `VERSION`, reports 5.10.55+ vermagic and a `modeset` parameter, and passes
`scripts/check-drm-abi.sh` against its own released 26.10.13 DRM provider pack.
None introduces DRM imports absent from the physically successful EPYC7002
reference, and none retains the old-path `drm_gem_handle_delete` or
`drm_master_get` import. Build logs are in `out/build-logs/580-proprietary-*-fullheaders-20261016.log`.

Userspace and GSP were reused from `out/release-assets-nvidia/shared/580/`;
no per-platform copies were generated. `bash scripts/check-shared-nvidia-layers.sh`
passed after the builds.

## Physical validation and promotion

The user subsequently confirmed normal physical-device KMS testing for all
three packs. They were copied into the regular proprietary asset directory:
`out/release-assets-nvidia/kver5-580-proprietary/`. Each promoted file was
byte-compared with its build output and its SHA-256 matched the values above.
This closes the earlier “unverified candidate” status; it is no longer
accurate to describe these three as build-only successes.

The reproducible one-platform builder is
`scripts/kms-compat/580.173.02/build-remaining-kms-pilot.sh`. Its exact provider
build inputs and logs are local under `out/` and are not included in this
commit; a fresh checkout must prepare matching platform inputs before using
the recipe.
