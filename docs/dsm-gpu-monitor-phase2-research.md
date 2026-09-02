# DSM GPU Monitor bridge — Phase 2 experimental research

This branch investigates a DSM Resource Monitor bridge for the already
working, read-only NVML telemetry collector.  It is **not** a release feature
and must not be added to the Phase 1 monitor SPK.

## Scope

- Initial target: SA6400 (`epyc7002`), DSM 7.4.1 only.
- Required input: a stock DSM baseline with the open `syno-nvidia-driver`
  installed and working.
- Required output: an evidence-backed, package-owned way for
  `SYNO.Core.System.Utilization` to return the established `gpu` object.

## Non-negotiable safety boundary

The experiment must not redistribute or copy opaque pdbear files.  It must
not replace `/usr/lib/libsynogpuinfo.so.7`, `/usr/lib/libsynosnmp.so.1`,
`/usr/lib/libnetsnmpmibs.so.40`, or `SYNO.Core.System.so` as part of a default
installation.  No global `LD_PRELOAD`, no permanent daemon, and no
unversioned DSM/platform compatibility claim are permitted.

## Evidence collection

On the target, run the following as root:

```sh
/path/to/syno_nvidia_driver/monitor-spk/phase2/collect-dsm-gpu-abi.sh
```

Run the source script directly until it is packaged into a separate
experimental artifact.  It writes a timestamped archive in `/tmp`; it only
reads system state.

The archive records: the exact DSM/kernel identity, Resource Monitor API
response, GPU capability flags, core/system-library hashes, UI references,
SNMP process state, NVIDIA modules, and the package-owned NVML JSON result.

## Acceptance gate before any bridge code

1. Identify a supported extension or interposition point with stable ABI
   evidence for the exact DSM release.
2. Demonstrate a reversible bridge that changes no DSM-owned file.
3. Confirm that the Resource Monitor API returns values matching NVML within
   one sampling interval.
4. Verify uninstall restores the baseline hashes and leaves no process or
   configuration entry behind.

If no supported extension point is found, Phase 2 remains a diagnostic tool;
we do not imitate pdbear by installing opaque library overlays.

## First evidence: SA6400 / DSM 7.4.1

The initial read-only run against `epyc7002 / DSM 7.4.1` with the open NVIDIA
driver and a Quadro P1000 established the following:

- The package-owned NVML collector reports valid GPU and VRAM values.
- `SYNO.Core.System.GpuInfo` is a registered DSM API with the `list` method,
  but returns `{ "support_gpu": false }` on the stock system.
- `SYNO.Core.System.Utilization` has no `gpu` object on that same system.
- Resource Monitor already contains GPU and GPU-memory charts.  Its UI gate
  is `support_nvidia_gpu="yes"`, but the charts require the absent `gpu`
  object from Utilization.
- The relevant private modules are
  `/usr/syno/synoman/webapi/lib/SYNO.Core.System.GpuInfo.so` and
  `/usr/syno/synoman/webapi/lib/SYNO.Core.System.Utilization.so`, not a
  package-owned plugin interface.

Therefore setting the UI flag alone is intentionally rejected: it would show
an empty GPU panel and would not implement monitoring.  No supported
extension point has been identified yet.  The remaining Phase 2 work is ABI
research only; a shipping bridge remains blocked unless it can be made
package-owned and fully reversible without replacing DSM private modules.
