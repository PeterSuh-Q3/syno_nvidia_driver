# DSM GPU Monitor Integration SPK — design

## Purpose

Provide an **optional**, separately installable SPK that makes a working
physical/passthrough NVIDIA GPU visible to DSM 7.4 Resource Monitor as **GPU**
and **GPU Memory**.  It is not a driver, CUDA package, transcoding package, or
a replacement for `nvidia-smi`.

The base `syno-nvidia-driver` package remains responsible for kernel modules,
NVIDIA userspace libraries, device nodes, and media-server integration.  This
package is installed only by users who explicitly want DSM UI telemetry.

## Evidence from the 2026-09-02 reference system

Reference: SA6400 / epyc7002 / DSM 7.4.1 / Quadro P1000 / pdbear NVIDIA
Runtime 550.163.01.

While the P1000 was under load, NVIDIA reported 34–37% GPU utilization and
about 542 MiB VRAM in use.  DSM's existing `SYNO.Core.System.Utilization`
WebAPI returned the matching object below:

```json
{
  "gpu": {
    "device": "Gpu",
    "gpu_utilization": 35,
    "gpu_memory_total": 4194304,
    "gpu_memory_used": 555008,
    "gpu_memory_free": 3571712,
    "gpu_memory_utilization": 13
  }
}
```

`gpu_memory_*` is expressed in KiB.  `gpu_utilization` is a percentage.  The
stock DSM Resource Monitor frontend already contains GPU and GPU-memory panels;
it shows them when this object is supplied.

The reference package enables `support_gpu_info="yes"` and
`support_nvidia_gpu="yes"`, and replaces these DSM libraries:

- `/usr/lib/libsynogpuinfo.so.7`
- `/usr/lib/libsynosnmp.so.1`
- `/usr/lib/libnetsnmpmibs.so.40`
- `/usr/syno/synoman/webapi/lib/SYNO.Core.System.so`

`snmpd` and `synosnmpcd` load the SNMP libraries.  This proves the integration
path, but **does not authorize copying those opaque binaries into this
project** or overwriting arbitrary DSM versions.

## Package boundary

```text
syno-nvidia-driver                 dsm-nvidia-gpu-monitor (optional)
──────────────────                 ─────────────────────────────────
kernel modules                     compatibility gate and backup manager
NVIDIA userspace / NVML       ──▶  DSM telemetry adapter
/dev/nvidia*                       WebAPI / Resource Monitor integration
Jellyfin / Plex helpers            diagnostics and transactional restore
```

Prerequisite: a supported `syno-nvidia-driver` release must already be
installed, NVIDIA modules must be loaded, and a real `nvidia-smi` query must
succeed.  The monitor SPK must never install a driver or make a GPU appear
where the driver cannot initialize it.

## Required DSM data contract

The implementation must make this existing request return a `gpu` object:

```sh
synowebapi --exec \
  api=SYNO.Core.System.Utilization method=get version=1 type=current
```

Required fields:

| Field | Source | Unit / rule |
| --- | --- | --- |
| `device` | fixed | `Gpu` |
| `gpu_utilization` | NVML GPU utilization | integer, 0–100 |
| `gpu_memory_total` | NVML total VRAM | KiB |
| `gpu_memory_used` | NVML used VRAM | KiB |
| `gpu_memory_free` | total minus used | KiB |
| `gpu_memory_utilization` | used / total | rounded integer, 0–100 |

NVML is the preferred collector.  `nvidia-smi --query-gpu=...` may be used
only as a diagnostic fallback; it must not become a privileged shell parser or
a permanently running polling daemon.

## Delivery phases

### Phase 0 — compatibility research (no shipped system modifications)

1. Compare stock DSM 7.4.1 and reference-library exported symbols, dynamic
   dependencies, AppArmor policy, and API registrations.
2. Determine whether DSM offers a supported/isolated WebAPI extension path
   (for example a package-owned API library registered through DSM tooling).
3. Verify whether `SYNO.Core.System.Utilization` can be augmented without
   replacing `SYNO.Core.System.so`.
4. Record exact API response and NVML correlation under idle and transcoding
   load.

Exit criterion: a reproducible integration point, or a written finding that
the endpoint is inseparable from DSM's private ABI.

### Phase 1 — package-owned collector and diagnostics

Build a package-owned, root-owned helper that exposes a read-only status
command such as:

```sh
syno-nvidia-gpu-monitor status --json
```

It validates driver readiness and emits the six contract values without
altering DSM.  This creates an independently testable NVIDIA telemetry layer.

### Phase 2 — opt-in DSM bridge (experimental)

Only after Phase 0 finds a compatible integration point, create a bridge SPK
for one exact DSM/platform family at a time.  The initial allow-list is
`epyc7002 / DSM 7.4.1`; do not claim universal support.

If a bridge requires a DSM library overlay, it is a separate experimental
sub-feature, not the default monitor installation.  It may ship only when its
source/licensing and ABI provenance are understood.  A pdbear binary extracted
from another package is not an acceptable redistribution source.

### Phase 3 — validation and expansion

Validate idle, NVENC, NVDEC, CUDA, reboot, package upgrade, uninstall, and
DSM update behavior.  Add one DSM/platform tuple only after it passes the same
matrix.

## Safety requirements

- No automatic installation with the NVIDIA driver.
- No global `LD_PRELOAD`, no replacement of `/usr/bin/nvidia-smi`, and no
  background process that polls the GPU continuously.
- Do not modify `synoinfo.conf` until the bridge is confirmed compatible.
- Before any system file change, record its SHA-256, owner, mode, and a backup
  outside the package target directory.
- Refuse installation when a target file hash is unknown, a previous monitor
  overlay is detected, or the DSM/platform tuple is not allow-listed.
- Restore on uninstall only when the installed file is the exact monitor-owned
  version; otherwise leave it untouched and report the conflict.
- Restart only the minimum DSM services required by the validated bridge; use a
  reboot as the documented recovery path if DSM cannot safely reload them.
- Every privileged backend and its payload must be root-owned and non-writable
  by the package account, following the driver package's hardened helper model.

## Test matrix

| Test | Expected result |
| --- | --- |
| No NVIDIA driver | monitor install is refused; no DSM changes |
| Driver loaded, idle GPU | GPU panels appear; all utilization values are 0 |
| NVENC/Jellyfin load | WebAPI GPU and VRAM values match NVML within sampling interval |
| CUDA load | GPU utilization and VRAM update without a media-server dependency |
| Reboot | driver and monitor recover without manual action |
| Monitor uninstall | stock files/configuration are restored exactly |
| DSM upgrade | package disables itself on unknown ABI until revalidated |

## Non-goals

- Making unsupported NVIDIA hardware work.
- DVA GPU model spoofing or license changes.
- Per-process GPU attribution in DSM Resource Monitor.
- AMD telemetry in this package.  AMD can later reuse the contract through a
  separate collector based on DRM/sysfs or libdrm, but must remain a separate
  project/package.
