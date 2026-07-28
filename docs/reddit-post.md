An open, **no-auth NVIDIA driver for Synology DSM** — physical / passthrough GPUs
only, **no vGPU and no license server**. One installer command, four driver
branches (470 / 535 / 550 / **580**), auto-matched to your platform and DSM kernel.

Everything is open source and the prebuilt kernel modules are on GitHub Releases.
Newly added: the **580 branch**, verified on real hardware including Plex hardware
transcoding — plus a section below on what CUDA version your GPU can *actually*
run, which trips up a lot of people.

---

## 🚀 Install (on a running DSM)

**Requirements:** root/`sudo`, internet, a **supported kver5 (5.10.55) platform**
(all 7 — see the support matrix below)
with an NVIDIA GPU (physical or passthrough). The installer auto-detects your
platform + GPU and refuses to run on anything it can't support.

    curl -sL https://raw.githubusercontent.com/PeterSuh-Q3/syno_nvidia_driver/main/install.sh | sudo bash

It walks you through 8 steps — platform check → GPU detection → **version choice
(1=535 / 2=550 / 3=470 / 4=580)** → optional NVENC ffmpeg for the Jellyfin package
— then downloads, installs, loads the driver and verifies with `nvidia-smi`.
The installer highlights the branch recommended for the GPU it found and tells you
the **highest CUDA version that GPU can actually run**.

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
      compatible driver branches: 580, 535, 550, 470   recommended: 580
    ▶ Step 5/8  Choose driver version
      1) 535 : 535.230.02 (verified)  (Production/LTS, Maxwell..Ada)
      2) 550 : 550.163.01 (build-ok)  (newest)
      3) 470 : 470.256.02   (legacy LTSB, Kepler..Ampere; for older GPUs)
      4) 580 : 580.173.02  <= recommended for your GPU  (newest branch, Maxwell..Blackwell; highest CUDA)
      Your GPU tops out at CUDA 12.9 - set by its compute capability, not by the driver.
      Select [1=535 / 2=550 / 3=470 / 4=580] (default 4):   ✔ selected driver 580.173.02
    ▶ Step 6/8  NVENC ffmpeg (for SynoCommunity Jellyfin package)
      ! no ffmpeg layer published for 580.173.02; skipping
      About to install:  driver 580.173.02 for epyc7002, ffmpeg=false
      Proceed? [Y/n]: 
    ▶ Step 7/8  Downloading layers
      ↓ kernel modules
      ############################################################ 100%
      ↓ userspace libraries
      ############################################################ 100%
      ✔ download complete
    ▶ Step 8/8  Installing
      ✔ kernel modules -> /usr/lib/modules
      ✔ userspace -> /usr/local/nvidia/lib  (+ /usr/lib symlinks)
      ✔ boot hook installed (/usr/local/etc/rc.d/nvidia.sh)
      ✔ SUCCESS  driver 580.173.02 installed and GPU is live:
        Tue Jul 28 23:17:18 2026
        +-----------------------------------------------------------------------------------------+
        | NVIDIA-SMI 580.173.02             Driver Version: 580.173.02     CUDA Version: 13.0     |
        +-----------------------------------------+------------------------+----------------------+
        | GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
        | Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
        |                                         |                        |               MIG M. |
        |=========================================+========================+======================|
        |   0  Quadro P620                    Off |   00000000:06:00.0 Off |                  N/A |
        | 34%   46C    P0            N/A  /  N/A  |       0MiB /   2048MiB |      0%      Default |
        |                                         |                        |                  N/A |
        +-----------------------------------------+------------------------+----------------------+
      run nvidia-smi anytime

*(colored version of the same run: [PNG](https://raw.githubusercontent.com/PeterSuh-Q3/syno_nvidia_driver/main/docs/install-580.png))*

> Real run on **Synology SA6400 (epyc7002) · Quadro P620 · DSM 7.4** installing
> **580.173.02** — verified 2026-07-28, including Plex hardware transcoding.

A boot hook (`/usr/local/etc/rc.d/nvidia.sh`) is installed so the driver reloads
automatically after a reboot. Run `nvidia-smi` any time to check the GPU.

> **⚠️ Restart Plex / Jellyfin after installing**
> Both enumerate GPUs **once, at their own startup**, and cache the result. If the
> package was already running when you installed (or removed) the driver, its
> hardware-transcoding device list is stale — the GPU simply will not appear in the
> settings, and transcodes fall back to software or fail.
>
> `sudo /usr/syno/bin/synopkg restart PlexMediaServer`
>
> This is by far the most common "the driver is installed but transcoding doesn't
> work" cause. It is **not** a driver/CUDA incompatibility.

### Verifying the install

The driver creates its device nodes on load. Checking them is the quickest way to
confirm a healthy install — and the first thing to look at if an app cannot see the GPU:

    $ sudo ls -l /dev/nvidia*
    crw-rw-rw- 1 root root  240,   0 Jul 28 23:17 /dev/nvidia-uvm   # CUDA unified memory - required by CUDA
    crw-rw-rw- 1 root root  240,   1 Jul 28 23:17 /dev/nvidia-uvm-tools
    crw-rw-rw- 1 root root  195,   0 Jul 28 23:17 /dev/nvidia0   # one node per GPU
    crw-rw-rw- 1 root root  195, 255 Jul 28 23:17 /dev/nvidiactl   # driver control node

    /dev/nvidia-caps:
    total 0
    cr-------- 1 root root  243,   1 Jul 28 23:17 nvidia-cap1
    cr--r--r-- 1 root root  243,   2 Jul 28 23:17 nvidia-cap2   # MIG capabilities (unused on consumer GPUs)

    $ lsmod | grep nvidia
    nvidia_drm             16384  0
    nvidia_uvm           1454080  4
    nvidia              103940096  168 nvidia_uvm

    $ sudo nvidia-smi --query-gpu=name,compute_cap,driver_version --format=csv
    name, compute_cap, driver_version
    Quadro P620, 6.1, 580.173.02      # cc 6.1 = Pascal -> CUDA 12.9 max

*(colored version: [PNG](https://raw.githubusercontent.com/PeterSuh-Q3/syno_nvidia_driver/main/docs/verify-580.png))*

| Node | Major | What it is |
|---|:---:|---|
| `/dev/nvidia0` | 195 | The GPU itself — **one node per physical GPU**. A second card appears as `nvidia1`. |
| `/dev/nvidiactl` | 195 | Driver control node; every client opens this first. |
| `/dev/nvidia-uvm` | 240 | Unified memory — **CUDA will not work without it**. |
| `/dev/nvidia-uvm-tools` | 240 | Debug/profiling companion to UVM. |
| `/dev/nvidia-caps/*` | 243 | MIG capability nodes; unused outside datacenter GPUs. |

What a healthy install looks like:

- **`nvidia0` count matches your GPU count.** If you see `nvidia0`…`nvidia7` on a
  single-GPU box, something created phantom nodes.
- **`nvidia_uvm` is loaded.** Without it `nvidia-smi` may still work while every
  CUDA application fails.
- `nvidia_modeset` / `nvidia_drm` missing is **normal on DSM** — Synology ships no
  `backlight.ko`. They are display-only and irrelevant to compute and NVENC/NVDEC.
- Permissions are `crw-rw-rw-`, so Plex, Jellyfin and containers can open them
  without extra setup.

If the nodes are missing entirely, the modules did not load — re-run the installer
or check `dmesg | grep -i nvrm`.

### NVENC ffmpeg (Jellyfin package)
Answer **y** at Step 6 to also install an NVENC-capable `ffmpeg` at
`/usr/local/nvidia/bin/ffmpeg`. Then in Jellyfin set **Dashboard → Playback →
FFmpeg path** to that binary. (Plex has its own transcoder and does not need this.)

## 🧹 Uninstall

    curl -sL https://raw.githubusercontent.com/PeterSuh-Q3/syno_nvidia_driver/main/uninstall.sh | sudo bash

*(what the uninstaller prints: [screenshot](https://github.com/PeterSuh-Q3/syno_nvidia_driver/blob/main/docs/uninstall.svg))*

---

## Supported platforms & driver versions

All **kver5 (kernel 5.10.55)** Synology platforms are supported. Each cell is a
prebuilt `.ko` on the [`nvidia`](https://github.com/PeterSuh-Q3/syno_nvidia_driver/releases/tag/nvidia)
Release; the shared userspace layer (`nv-userspace-<ver>.tgz`) is identical per
driver version across every platform.

| Platform | Example models | 470.256.02 | 535.230.02 | 550.163.01 | **580.173.02** |
|---|---|:---:|:---:|:---:|:---:|
| `epyc7002`      | SA6400                         | ✅ | ✅ | ✅ | **✅** |
| `epyc7003`      | FS6420                         | ✅ | ✅ | ✅ | — |
| `epyc7003ntb`   | PAS7700                        | ✅ | ✅ | ✅ | — |
| `icelaked`      | FS3420 / RS3626xs / RS4826xs+  | ✅ | ✅ | ✅ | — |
| `v1000nk`       | (Ryzen Embedded V1000, no-key) | ✅ | ✅ | ✅ | — |
| `r1000nk`       | (Ryzen Embedded R1000, no-key) | ✅ | ✅ | ✅ | — |
| `geminilakenk`  | DS225+ / DS425+                | ✅ | ✅ | ✅ | — |

| Branch | GPU coverage | Native CUDA | Notes |
|---|---|:---:|---|
| **470.256.02** | Kepler … Ampere | 11.4 | Legacy LTSB — for old GPUs 535+ dropped. ffmpeg layer pinned to `jellyfin-ffmpeg 5.1.2-9` (NVENC API 11.1); never pair it with the 535/550 ffmpeg. |
| **535.230.02** | Maxwell … Ada | 12.2 | Production/LTS. Verified on P620. ffmpeg `6.0.1-8` (NVENC 12.0). |
| **550.163.01** | Maxwell … Ada | 12.4 | ffmpeg `7.0.2-9` (NVENC 12.1). |
| **580.173.02** | Maxwell … **Blackwell** | **13.0** | Newest, and the **last branch supporting Maxwell/Pascal/Volta**. Verified on P620 incl. Plex HW transcoding. Turing+ needs GSP firmware (**not shipped yet**). No ffmpeg layer yet. |

- **580 is the recommended branch for most GPUs.** It supersedes 535/550 (same
  Maxwell→Ada coverage, plus Blackwell) and raises what Pascal can run from CUDA
  12.4 to **12.9**. Only Kepler-era cards still need 470.
- ⚠️ **580 on Turing or newer** (RTX 20/30/40/50, T4, A10, L4 …) requires GSP
  firmware, which is not packaged yet — the installer warns and stops. Use 535/550
  on those GPUs for now.
- One `.ko` per platform covers **DSM 7.1–7.4** because `CONFIG_MODVERSIONS` is off
  and the vermagic (`5.10.55+ SMP mod_unload`) is identical across those DSM
  releases — only the vermagic gates module load.

---

## CUDA versions — what actually applies to your GPU

This trips people up constantly, so it is worth being precise. **Two independent
things** decide which CUDA you can run:

| | Set by | What it limits |
|---|---|---|
| **Driver** | the branch you install | the highest CUDA API the driver speaks |
| **GPU architecture** (compute capability) | the silicon — cannot be changed | which CUDA toolkit versions can *generate code* for it |

CUDA 13.0 dropped code generation for everything below **compute capability 7.5
(Turing)**. So on a Pascal card, installing 580 does **not** unlock CUDA 13.0 —
there is simply no Pascal binary in a CUDA 13 build. Drivers are backward
compatible, so a 580 driver happily runs CUDA 12.x applications.

| Compute cap. | Architecture | Example GPUs | **Max usable CUDA** |
|:---:|---|---|:---:|
| 6.0 / 6.1 | Pascal | **Quadro P620 / P1000**, Tesla **P4 / P40 / P100**, GTX 10xx | **12.9** |
| 7.0 | Volta | Tesla V100 | 12.9 |
| **7.5** | **Turing** | **Tesla T4**, RTX 20xx | **13.0** |
| 8.0 / 8.6 | Ampere | A100 / A10, RTX 30xx | 13.0 |
| 8.9 | Ada | L4 / L40S, RTX 40xx | 13.0 |
| 12.0 | Blackwell | RTX 50xx | 13.0 |

**7.5 is the dividing line.** Below it the ceiling is 12.9; at or above it, 13.0.
Higher-capability cards also run every lower CUDA version.

### How to check your GPU's real CUDA ceiling

    sudo nvidia-smi --query-gpu=name,compute_cap,driver_version --format=csv

    name, compute_cap, driver_version
    Quadro P620, 6.1, 580.173.02      →  cc 6.1 = Pascal  →  CUDA 12.9 max

> **Do not read the CUDA version off the `nvidia-smi` header.** On the P620 above it
> prints `CUDA Version: 13.0`, but that is only the *driver's* maximum — the GPU
> still cannot run CUDA 13.0. `compute_cap` is the value that decides.

`compute_cap` requires driver **≥ 510**, so it is unavailable on 470. There, read
the model name instead (`sudo nvidia-smi -q | grep "Product Name"`) and look it up
in the table above.

To check what an application actually gets, query it from inside your container:

    python3 -c "import torch; print(torch.version.cuda, torch.cuda.get_device_capability(), torch.cuda.is_available())"
    # e.g. 12.4 (6, 1) True   →  toolkit 12.4, compute capability 6.1, usable

### CUDA is irrelevant for transcoding

Plex and Jellyfin do **not** use the CUDA toolkit to transcode — they use the
dedicated **NVENC/NVDEC** engines via `libnvidia-encode.so.1` / `libnvcuvid.so.1`.
NVENC is backward compatible, so a newer driver runs a player's older NVENC code
fine. If hardware transcoding is missing, the cause is almost always the stale
device list described above (restart the package), not a CUDA version mismatch.

The one direction that *does* break is the opposite one: an **old driver with a
too-new ffmpeg** (e.g. 470 + an NVENC 12.x build). That is why each branch is
pinned to a matching ffmpeg layer.

### Why kver5 only?

The driver ships as a kernel module (`.ko`) that must match the **exact Synology
kernel** it loads into. Two hard constraints make kver5 the practical target:

1. **Kernel API vs. driver branch.** NVIDIA's open kernel-interface glue tracks
   modern kernel APIs. The **470 / 535 / 550 / 580** branches all compile cleanly
   against **5.10.55** (580 needs kernel ≥ 4.15 per NVIDIA), but on the older
   **kver4 (4.4.x, ~2016)** and **kver3 (3.10.x)** Synology kernels the newer glue
   fails to build — those kernels would need a *legacy* branch (470 / 390), which
   in turn drops support for newer GPUs. So "one modern branch for every platform"
   only holds on kver5.
2. **Toolchain + kernel tree availability.** Builds run against the per-platform
   `/opt//build` kernel tree inside the `dante90/syno-compiler`
   container. The kver5 trees are the ones wired up and validated here.

kver4 / kver3 platforms are therefore **out of scope for the 535/550/580 line**. They
are technically buildable with a legacy branch, but that is a separate matrix
(different branch, different GPU coverage) and is not currently shipped.

---

## Notes / limits

- The `.ko` are **unsigned**, so DSM logs `module verification failed … tainting`.
  That is benign — `MODULE_SIG_FORCE` is not set and the modules load fine.
- `nvidia-modeset` / `nvidia-drm` may fail with `Unknown symbol backlight_device_register`.
  Also benign: DSM ships no `backlight.ko`. Those modules are display-only and are
  irrelevant to compute and NVENC/NVDEC transcoding.
- **GSP firmware is not packaged yet**, so 580 is validated for pre-Turing GPUs
  only. `install.sh` detects GPUs that need it and stops rather than installing a
  driver that would fail to initialise. Use 535/550 on Turing+ for now.
- Physical / passthrough GPUs only — there is no vGPU or license server support,
  and none is planned.

## Source

Everything (build scripts, installer, prebuilt layers) is open:
**https://github.com/PeterSuh-Q3/syno_nvidia_driver**

Only NVIDIA's *open* kernel-interface glue is recompiled against the Synology
kernel tree and linked with the stock closed `nv-kernel` blob, so the resulting
`.ko` has a vermagic that matches DSM exactly — which is what makes it load at all.
