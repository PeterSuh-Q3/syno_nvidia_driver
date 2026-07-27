# syno_nvidia_driver

No-auth NVIDIA driver for Synology DSM — **physical / passthrough GPUs only, no
vGPU / license server** (unlike pdbear's closed SPK). Multiple driver versions
per GPU, auto-matched to your platform + DSM kernel.

---

## 🚀 Install (on a running DSM)

**Requirements:** root/`sudo`, internet, a **supported kver5 platform**
(`epyc7002` / `geminilakenk` — e.g. SA6400) with an NVIDIA GPU (physical or
passthrough). The installer auto-detects your platform + GPU and refuses to run
on anything it can't support.

```bash
sudo curl -skLO https://raw.githubusercontent.com/PeterSuh-Q3/syno_nvidia_driver/main/install.sh
sudo bash install.sh
```

It walks you through 8 steps — platform check → GPU detection → **version choice
(1=535 / 2=550)** → optional NVENC ffmpeg for the Jellyfin package — then
downloads, installs, loads the driver and verifies with `nvidia-smi`.

<details open>
<summary><b>Example run</b> (SA6400 / epyc7002 · Quadro P620 · verified 2026-07-27)</summary>

```text
  ╔══════════════════════════════════════════════════════════╗
  ║        NVIDIA driver for Synology DSM  (no-auth)          ║
  ║        physical / passthrough GPU · installer            ║
  ╚══════════════════════════════════════════════════════════╝

▶ Step 1/8  Privilege check
  ✔ running as root
▶ Step 2/8  Fetching driver catalog
  ✔ catalog loaded
▶ Step 3/8  Platform support check
  platform : epyc7002   kernel: 5.10.55+
  ✔ supported (kver 5.10.55)
▶ Step 4/8  NVIDIA GPU detection
  ✔ detected: Quadro P620  (10de:1cb6, Pascal GP107)
  compatible driver branches: 535, 550, 525   recommended: 535
▶ Step 5/8  Choose driver version
  1) 535 : 535.230.02 (verified) <= recommended for your GPU
  2) 550 : 550.163.01 (build-ok)
  Select [1=535 / 2=550] (default 1): 1
  ✔ selected driver 535.230.02
▶ Step 6/8  NVENC ffmpeg (for SynoCommunity Jellyfin package)
  Also install NVENC ffmpeg? [y/N]: n
  ✔ skipping ffmpeg
  About to install:  driver 535.230.02 for epyc7002, ffmpeg=false
  Proceed? [Y/n]: y
▶ Step 7/8  Downloading layers
  ↓ kernel modules
  ↓ userspace libraries
  ✔ download complete
▶ Step 8/8  Installing
  ✔ kernel modules -> /usr/lib/modules
  ✔ userspace -> /usr/local/nvidia/lib  (+ /usr/lib symlinks)
  ✔ boot hook installed (/usr/local/etc/rc.d/nvidia.sh)
  ✔ SUCCESS  driver 535.230.02 installed and GPU is live:
    +---------------------------------------------------------------------------------------+
    | NVIDIA-SMI 535.230.02             Driver Version: 535.230.02   CUDA Version: 12.2     |
    |-----------------------------------------+----------------------+----------------------+
    |   0  Quadro P620                    Off | 00000000:06:00.0 Off |                  N/A |
    | 46%   51C    P0              N/A /  N/A |      0MiB /  2048MiB |      2%      Default |
    +---------------------------------------------------------------------------------------+
  run nvidia-smi anytime · uninstall with sudo ./uninstall.sh
```
</details>

A boot hook (`/usr/local/etc/rc.d/nvidia.sh`) is installed so the driver reloads
automatically after a reboot. Run `nvidia-smi` any time to check the GPU.

### NVENC ffmpeg (Jellyfin package)
Answer **y** at Step 6 to also install an NVENC-capable `ffmpeg` at
`/usr/local/nvidia/bin/ffmpeg`. Then in Jellyfin set **Dashboard → Playback →
FFmpeg path** to that binary. (Plex has its own transcoder and does not need this.)

## 🧹 Uninstall

```bash
sudo bash uninstall.sh
```

<details>
<summary><b>Example run</b></summary>

```text
▶ Step 1/5  Privilege check
  ✔ running as root
▶ Step 3/5  Unloading kernel modules
  ✔ unloaded nvidia_drm
  ✔ unloaded nvidia_uvm
  ✔ unloaded nvidia
  ✔ all nvidia modules unloaded
▶ Step 5/5  Removing driver files
  ✔ removed 110 /usr/lib symlinks
  ✔ removed nvidia*.ko from /usr/lib/modules
  ✔ removed /usr/local/nvidia
  ✔ Uninstall complete.  No NVIDIA driver remains.
```
</details>

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
