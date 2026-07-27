# syno_nvidia_driver

No-auth NVIDIA driver for Synology DSM — **physical / passthrough GPUs only, no
vGPU / license server** (unlike pdbear's closed SPK). Multiple driver versions
per GPU, auto-matched to your platform + DSM kernel.

---

## 🚀 Install (on a running DSM)

**Requirements:** root/`sudo`, internet, a **supported kver5 (5.10.55) platform**
(all 7 — see the [support matrix](#supported-platforms--driver-versions) below)
with an NVIDIA GPU (physical or passthrough). The installer auto-detects your
platform + GPU and refuses to run on anything it can't support.

```bash
curl -sL https://raw.githubusercontent.com/PeterSuh-Q3/syno_nvidia_driver/main/install.sh | sudo bash
```

It walks you through 8 steps — platform check → GPU detection → **version choice
(1=535 / 2=550)** → optional NVENC ffmpeg for the Jellyfin package — then
downloads, installs, loads the driver and verifies with `nvidia-smi`.

<p align="center">
  <img src="docs/install.svg" alt="install.sh run on SA6400 with a Quadro P620" width="760">
</p>

> Real run on **Synology SA6400 (epyc7002) · Quadro P620 · DSM 7.4.1** — verified 2026-07-27.

A boot hook (`/usr/local/etc/rc.d/nvidia.sh`) is installed so the driver reloads
automatically after a reboot. Run `nvidia-smi` any time to check the GPU.

### NVENC ffmpeg (Jellyfin package)
Answer **y** at Step 6 to also install an NVENC-capable `ffmpeg` at
`/usr/local/nvidia/bin/ffmpeg`. Then in Jellyfin set **Dashboard → Playback →
FFmpeg path** to that binary. (Plex has its own transcoder and does not need this.)

## 🧹 Uninstall

```bash
curl -sL https://raw.githubusercontent.com/PeterSuh-Q3/syno_nvidia_driver/main/uninstall.sh | sudo bash
```

<p align="center">
  <img src="docs/uninstall.svg" alt="uninstall.sh run" width="660">
</p>

---

## Supported platforms & driver versions

All **kver5 (kernel 5.10.55)** Synology platforms are supported. Each cell is a
prebuilt `.ko` on the [`nvidia`](https://github.com/PeterSuh-Q3/syno_nvidia_driver/releases/tag/nvidia)
Release; the shared userspace layer (`nv-userspace-<ver>.tgz`) is identical per
driver version across every platform.

| Platform | Example models | 535.230.02 | 550.163.01 |
|---|---|:---:|:---:|
| `epyc7002`      | SA6400                         | ✅ | ✅ |
| `epyc7003`      | FS6420                         | ✅ | ✅ |
| `epyc7003ntb`   | PAS7700                        | ✅ | ✅ |
| `icelaked`      | FS3420 / RS3626xs / RS4826xs+  | ✅ | ✅ |
| `v1000nk`       | (Ryzen Embedded V1000, no-key) | ✅ | ✅ |
| `r1000nk`       | (Ryzen Embedded R1000, no-key) | ✅ | ✅ |
| `geminilakenk`  | DS225+ / DS425+                | ✅ | ✅ |

- **535.230.02** — verified live on a **Quadro P620** (epyc7002 / DSM 7.4.1). NVENC
  12.0, pairs with the Jellyfin package's `jellyfin-ffmpeg 6.0.1-8`.
- **550.163.01** — newer branch (NVENC 12.1). Both branches cover Maxwell → Ada.
- One `.ko` per platform covers **DSM 7.1–7.4** because `CONFIG_MODVERSIONS` is off
  and the vermagic (`5.10.55+ SMP mod_unload`) is identical across those DSM
  releases — only the vermagic gates module load.

### Why kver5 only?

The driver ships as a kernel module (`.ko`) that must match the **exact Synology
kernel** it loads into. Two hard constraints make kver5 the practical target:

1. **Kernel API vs. driver branch.** NVIDIA's open kernel-interface glue tracks
   modern kernel APIs. The **535 / 550** branches compile cleanly against
   **5.10.55**, but on the older **kver4 (4.4.x, ~2016)** and **kver3 (3.10.x)**
   Synology kernels the same glue fails to build — those kernels would need a
   *legacy* driver branch (470 / 390), which in turn drops support for newer GPUs
   (Ampere / Ada). So "one modern branch for every platform" only holds on kver5.
2. **Toolchain + kernel tree availability.** Builds run against the per-platform
   `/opt/<platform>/build` kernel tree inside the `dante90/syno-compiler`
   container. The kver5 trees are the ones wired up and validated here.

kver4 / kver3 platforms are therefore **out of scope for the 535/550 line**. They
are technically buildable with a legacy branch, but that is a separate matrix
(different branch, different GPU coverage) and is not currently shipped.

---

## About (build / producer side)

Builds the **no-auth NVIDIA driver** (2-layer package) for Synology DSM kver5
platforms. Physical / passthrough GPUs only — **no vGPU / license server**
(unlike pdbear's closed SPK). Multiple driver versions per GPU.

This repo is the **build/producer** side. It borrows the
`dante90/syno-compiler:<DSM>` container (the same toolchain base mshell-modules
uses) but is otherwise independent of both mshell-modules and tcrp-addons.

## Where it fits

```
mshell-modules ── provides ──> dante90/syno-compiler:<DSM>  +  /opt/<platform>/build
                                        │ (container + kernel tree reused, not the repo tree)
                                        ▼
        THIS REPO (syno_nvidia_driver, cloned on build VM 192.168.45.139)
          build-nvidia.sh → 2-layer tgz → GitHub Release (tag: nvidia)
                                        │
                                        ▼
        tcrp-addons/nvidiadriver  ── consumer: install.sh + nvidia-index.json
          (references the Release URLs; loader fetches at build time → DSM)
```

Only NVIDIA's **open** kernel-interface glue is recompiled and linked against the
closed `nv-kernel` blob, so the `.ko` vermagic + `CONFIG_MODVERSIONS` CRCs match
the exact DSM kernel (the fix for the issue-#77 "Unknown symbol" failure).

## 2-layer packaging

| layer | file | scope |
|---|---|---|
| kernel | `nv-ko-<ver>-<platform>-<kvershort>.tgz` | **per platform** (~MB) |
| userspace | `nv-userspace-<ver>.tgz` | **per version** only, x86_64 shared across kver5 platforms |

## Build (on VM 192.168.45.139)

```bash
ssh dante90@192.168.45.139
git -C ~/syno_nvidia_driver pull            # always sync first
cd ~/syno_nvidia_driver
# download the .run once (open glue + closed nv-kernel blob)
curl -kLo run/NVIDIA-Linux-x86_64-535.183.06.run \
  https://us.download.nvidia.com/XFree86/Linux-x86_64/535.183.06/NVIDIA-Linux-x86_64-535.183.06.run
./run-on-vm.sh 535.183.06 epyc7002 7.4      # <ver> <platform> <DSM_VER>
```

Outputs land in `out/` with a printed `nvidia-index.json` fragment (incl. sha256).

## Publish

1. Upload both `out/*.tgz` to this repo's Release tagged **`nvidia`**.
2. Paste the printed fragment into `tcrp-addons/nvidiadriver/src/nvidia-index.json`
   and push tcrp-addons.

## Files

- [build-nvidia.sh](build-nvidia.sh) — runs inside the compiler container; builds both layers
- [run-on-vm.sh](run-on-vm.sh) — `sudo docker` wrapper for the build VM
- `run/` — put `NVIDIA-Linux-x86_64-<ver>.run` here (git-ignored)
- `out/` — build artifacts (git-ignored)

## Notes / limits

- `.ko` are unsigned → DSM logs `module verification failed … tainting` — benign
  (`MODULE_SIG_FORCE` not set, modules still load).
- Target is **kver5 (5.10.55)** where 525/535/550 build fine. On kver4 (4.4.x)
  newer branches may not compile — use a legacy branch (470).
- R515+ branches load **GSP firmware**; if a branch needs it, add the firmware
  blob to the userspace layer.

## Workflow rule

Source change → **commit/push here first** → on the VM **`git pull`** → then build.
Never build from uncommitted local changes.
