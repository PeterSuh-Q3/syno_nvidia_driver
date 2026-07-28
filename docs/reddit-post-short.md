An open, **no-auth NVIDIA driver for Synology DSM** — physical / passthrough GPUs
only, **no vGPU, no license server**. One command, four branches (470 / 535 / 550 /
**580**), auto-matched to your platform and DSM kernel. Newly added: **580**, verified
on real hardware including Plex hardware transcoding.

---

## 🚀 Install (on a running DSM)

**Requirements:** root/`sudo`, internet, a kver5 (5.10.55) platform + an NVIDIA GPU. The installer auto-detects platform and GPU and refuses anything it can't support.

    curl -sL https://raw.githubusercontent.com/PeterSuh-Q3/syno_nvidia_driver/main/install.sh | sudo bash

8 guided steps — platform check → GPU detection → version choice → optional NVENC
ffmpeg → download, install, load, verify. It recommends a branch for the GPU it finds
and tells you the **highest CUDA version that GPU can actually run**.

    ▶ Step 4/8  NVIDIA GPU detection
      ✔ detected: Quadro P620  (10de:1cb6, Pascal GP107)
      4) 580 : 580.173.02  <= recommended for your GPU  (newest branch, Maxwell..Blackwell; highest CUDA)
      Your GPU tops out at CUDA 12.9 - set by its compute capability, not by the driver.
      Select [1=535 / 2=550 / 3=470 / 4=580] (default 4):   ✔ selected driver 580.173.02
      ✔ SUCCESS  driver 580.173.02 installed and GPU is live:
        | NVIDIA-SMI 580.173.02             Driver Version: 580.173.02     CUDA Version: 13.0     |
        |   0  Quadro P620                    Off |   00000000:06:00.0 Off |                  N/A |

    ...(trimmed - full run in the screenshot link below)

*(colored version of the same run: [PNG](https://raw.githubusercontent.com/PeterSuh-Q3/syno_nvidia_driver/main/docs/install-580.png))*

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

*(colored version: [PNG](https://raw.githubusercontent.com/PeterSuh-Q3/syno_nvidia_driver/main/docs/verify-580.png))*

- `/dev/nvidia0` — the GPU itself, **one node per physical GPU** (a 2nd card is `nvidia1`)
- `/dev/nvidiactl` — driver control node, every client opens it first
- `/dev/nvidia-uvm` — unified memory, **CUDA does not work without it**
- `/dev/nvidia-caps/*` — MIG nodes, unused outside datacenter GPUs

Healthy install: `nvidia0` count == your GPU count; `nvidia_uvm` loaded (without it
`nvidia-smi` works but every CUDA app fails); missing `nvidia_modeset`/`nvidia_drm` is
**normal on DSM** (no `backlight.ko` — display-only, irrelevant to compute/NVENC);
perms `crw-rw-rw-` so Plex/Jellyfin/containers need no extra setup. No nodes at all
means the modules never loaded — re-run the installer or check `dmesg | grep -i nvrm`.

### NVENC ffmpeg (Jellyfin package)
Answer **y** at Step 6 to also install an NVENC-capable `ffmpeg` at
`/usr/local/nvidia/bin/ffmpeg`. Then in Jellyfin set **Dashboard → Playback →
FFmpeg path** to that binary. (Plex has its own transcoder and does not need this.)

## 🧹 Uninstall

    curl -sL https://raw.githubusercontent.com/PeterSuh-Q3/syno_nvidia_driver/main/uninstall.sh | sudo bash

---

## Supported platforms & driver versions

All **kver5 (kernel 5.10.55)** Synology platforms are supported. Each cell is a
prebuilt `.ko` on the [`nvidia`](https://github.com/PeterSuh-Q3/syno_nvidia_driver/releases/tag/nvidia)
Release; the shared userspace layer (`nv-userspace-VERSION.tgz`) is identical per
driver version across every platform.

**Platforms:** all 7 kver5 ones — `epyc7002` (SA6400), `epyc7003`, `epyc7003ntb`, `icelaked`, `v1000nk`, `r1000nk`, `geminilakenk` (DS225+/DS425+). 470/535/550 are built for all of them; **580 is epyc7002 only so far**.

| Branch | GPU coverage | Native CUDA | Notes |
|---|---|:---:|---|
| **470.256.02** | Kepler … Ampere | 11.4 | Legacy LTSB, for GPUs 535+ dropped |
| **535.230.02** | Maxwell … Ada | 12.2 | Production/LTS, verified on P620 |
| **550.163.01** | Maxwell … Ada | 12.4 | — |
| **580.173.02** | Maxwell … **Blackwell** | **13.0** | Newest; **last branch with Maxwell/Pascal/Volta**. Turing+ needs GSP (not shipped) |

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

**Two independent things** decide it: the **driver** (sets the highest CUDA API it
speaks) and your **GPU architecture / compute capability** (sets which CUDA toolkits
can *generate code* for it — fixed in silicon).

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

## Notes / limits

- Modules are **unsigned** → DSM logs `module verification failed … tainting`. Benign.
- **GSP firmware is not packaged yet**, so 580 is validated for pre-Turing GPUs only;
  the installer detects GPUs that need it and stops. Use 535/550 on Turing+ for now.
- Physical / passthrough GPUs only — no vGPU, no license server, none planned.

## Source

Everything (build scripts, installer, prebuilt layers) is open:
**https://github.com/PeterSuh-Q3/syno_nvidia_driver**

Only NVIDIA's *open* kernel-interface glue is recompiled against the Synology
kernel tree and linked with the stock closed `nv-kernel` blob, so the resulting
`.ko` has a vermagic that matches DSM exactly — which is what makes it load at all.
