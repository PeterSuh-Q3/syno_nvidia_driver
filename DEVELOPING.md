# Developing / Building

> Build-side notes for **syno_nvidia_driver**. If you only want to *install* the
> driver on a DSM box, you want the [README](README.md) instead.

---

## 📦 About

Builds the NVIDIA driver (2-layer package) for Synology DSM platforms on
kernel 5.10.55 and kernel 4.4. Physical / passthrough GPUs only — no vGPU, so
no license server to run (unlike pdbear's closed SPK). Multiple driver
versions per GPU. See the [README](README.md#-install) for what that means
for an end user.

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
| userspace | `nv-userspace-<ver>.tgz` | **per version** only, x86_64 shared across every platform and kernel |

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

### GSP firmware layer

GSP firmware is NVIDIA-supplied signed binary firmware, not code compiled by
this project. For a branch that needs it (Turing or newer), extract the
firmware from the same official `.run` file and create the release asset with:

```bash
scripts/make-gsp-layer.sh 595.99.02
```

This produces `out/nv-gsp-595.99.02.tgz`. The archive contains `gsp_*.bin`
files at its root so `scripts/build-spk.sh` can place them in the SPK runtime.
Upload it with the matching module and userspace archives, then update the
GPU-support index with the archive SHA-256 and the firmware-to-GPU mapping.

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
- On **5.10.55**, 470/535/550/580 all build fine (each verified — vermagic
  matches, `nvUvmInterface` exported). On **4.4.x**, 550 is the ceiling: 560+
  refuse outright with `#error "... older than Linux 4.15!"` (measured on
  560/570/575/580). Note the PAT compat patch below must be **skipped** on 4.4 —
  it targets 5.10 API and injects `__native_read_cr3`, which 4.4 lacks;
  `build-nvidia.sh` detects this from the kernel headers automatically.
- **Compat patches move between branches.** Synology builds with
  `CONFIG_X86_PAT` off, forcing NVIDIA's builtin-PAT path, which uses
  `__flush_tlb()` and `__write_cr4()` — neither usable from a module on 5.10.
  `build-nvidia.sh` rewrites both, but their *location* changes: ≤550 kept the CR4
  write in `common/inc/nv-linux.h`, 580 calls it directly in `nvidia/nv-pat.c`
  with a different argument shape. The patcher therefore searches the tree and
  **aborts the build if any call site survives** — a silently skipped patch used
  to surface only as an unrelated `native_write_cr4 undefined` modpost error.
- R515+ branches load **GSP firmware** on Turing and newer. Extracted from the
  official `.run` (it ships `gsp_tu10x.bin` + `gsp_ga10x.bin` only — no Ada/
  Blackwell blob), packaged as `nv-gsp-<ver>.tgz`, and deployed by `install.sh` to
  `/lib/firmware/nvidia/<ver>/` **before** the kernel module loads (GSP is
  requested via `request_firmware()` at probe time, so order matters).
  `/lib/firmware` lives on the same rw root as everything else here, so this
  persists across reboots with no redeploy needed. GPUs needing GSP with no
  bundled blob (Ada/Blackwell) still hit `install.sh`'s warning gate.
  **Caveat: wired up and unit-tested (download/sha256/placement), but not yet
  validated against real Turing/Ampere hardware** — the only box available this
  session has a Pascal GPU, which skips the GSP path entirely.

## Workflow rule

Source change → **commit/push here first** → on the VM **`git pull`** → then build.
Never build from uncommitted local changes.

## Build provenance and reproducibility

The 580 K5 EPYC7002/EPYC7003 comparison exposed a process gap: moving a build
from GitHub Actions to Docker Desktop is not inherently unsafe, but an ad-hoc
local command is hard to compare later if its exact script and inputs were not
committed or recorded. The same compiler image alone does not prove that two
builds used equivalent inputs or options. In this investigation, the historical
EPYC7002 success did not retain enough command/configuration provenance to
identify a single cause for its difference from EPYC7003; the available A/B
checks narrowed possibilities but did not establish that root cause.

For future platform comparisons, preserve the successful pilot path before
expanding the matrix. Both local Docker Desktop and any GitHub workflow should
call the same versioned build script, with platform-specific values passed as
explicit configuration rather than undocumented shell edits. Record at least:
the source commit and script hash, compiler image digest, NVIDIA `.run` hash,
platform/kernel build tree and its `.config`/`Module.symvers` identity, full
build command and environment/options, applied patches, conftest results,
build log, output archive hash, and module metadata. A successful result should
be reproducible from that record before it is treated as the reference method.
Keep diagnostic outputs separate from canonical release assets, and promote
them only after review.

---

<details>
<summary>🇰🇷 <b>한국어 (펼쳐 보기)</b></summary>

<br>

# 개발 / 빌드 가이드

> **syno_nvidia_driver**의 빌드 측 문서입니다. DSM에 드라이버를 *설치*하려는
> 것이라면 [README](README.md)를 보세요.

---

## 📦 소개

커널 5.10.55 및 커널 4.4 Synology DSM 플랫폼용 NVIDIA 드라이버(2층 패키지)를
빌드합니다. 물리 / passthrough GPU 전용 — vGPU를 쓰지 않으니 라이선스 서버도
필요 없습니다(pdbear의 폐쇄 SPK와 다름). GPU마다 여러 드라이버 버전을
제공합니다. 이게 일반 사용자에게 무슨 의미인지는 [README](README.md#-설치)
참고.

이 repo는 **빌드/생산자** 측입니다. `dante90/syno-compiler:<DSM>` 컨테이너(mshell-modules가
쓰는 것과 동일한 툴체인 base)를 빌려 쓰지만, mshell-modules · tcrp-addons 양쪽으로부터
독립적입니다.

### 구조상 위치

```
mshell-modules ── 제공 ──> dante90/syno-compiler:<DSM>  +  /opt/<platform>/build
                                     │ (컨테이너 + 커널 트리만 재사용, repo 트리는 아님)
                                     ▼
        이 REPO (syno_nvidia_driver, 빌드 VM 192.168.45.139에 클론)
          build-nvidia.sh → 2층 tgz → GitHub Release (tag: nvidia)
                                     │
                                     ▼
        tcrp-addons/nvidiadriver  ── 소비자: install.sh + nvidia-index.json
          (Release URL 참조; loader가 빌드 시점에 fetch → DSM)
```

NVIDIA의 **오픈** 커널 인터페이스 glue만 재컴파일해 폐쇄 `nv-kernel` blob과 링크하므로,
`.ko`의 vermagic + `CONFIG_MODVERSIONS` CRC가 정확한 DSM 커널과 일치합니다(이슈 #77의
"Unknown symbol" 실패에 대한 해결책).

### 2층 패키징

| 레이어 | 파일 | 범위 |
|---|---|---|
| 커널 | `nv-ko-<ver>-<platform>-<kvershort>.tgz` | **플랫폼별** (~MB) |
| userspace | `nv-userspace-<ver>.tgz` | **버전별** 1개, x86_64 공통(모든 플랫폼·커널 공유) |

### 빌드 (VM 192.168.45.139에서)

```bash
ssh dante90@192.168.45.139
git -C ~/syno_nvidia_driver pull            # 항상 먼저 동기화
cd ~/syno_nvidia_driver
# .run 을 한 번 받는다 (오픈 glue + 폐쇄 nv-kernel blob)
curl -kLo run/NVIDIA-Linux-x86_64-535.183.06.run \
  https://us.download.nvidia.com/XFree86/Linux-x86_64/535.183.06/NVIDIA-Linux-x86_64-535.183.06.run
./run-on-vm.sh 535.183.06 epyc7002 7.4      # <ver> <platform> <DSM_VER>
```

결과물은 `out/`에 생성되며, sha256을 포함한 `nvidia-index.json` fragment가 출력됩니다.

### 배포

1. `out/*.tgz` 두 개를 이 repo의 **`nvidia`** 태그 Release에 업로드합니다.
2. 출력된 fragment를 `tcrp-addons/nvidiadriver/src/nvidia-index.json`에 붙여넣고
   tcrp-addons를 push합니다.

### 참고 / 한계

- `.ko`는 서명되지 않아 DSM이 `module verification failed … tainting`을 남깁니다 —
  무해합니다(`MODULE_SIG_FORCE` 미설정, 모듈은 정상 로드).
- **5.10.55**에서는 470/535/550/580이 모두 정상 빌드됩니다(각각 검증 — vermagic
  일치, `nvUvmInterface` export 확인). **4.4.x**에서는 550이 상한이며, 560 이상은
  `#error "... older than Linux 4.15!"`로 즉시 거부합니다(560/570/575/580 실측).
  아래 PAT 호환 패치는 4.4에서 **건너뛰어야** 합니다 — 5.10 API를 겨냥해
  `__native_read_cr3`를 주입하는데 4.4에는 없는 심볼입니다. `build-nvidia.sh`가
  커널 헤더를 보고 자동 판별합니다.
- **호환 패치의 위치는 브랜치마다 이동합니다.** Synology는 `CONFIG_X86_PAT`를 끈 채
  빌드하므로 NVIDIA의 builtin-PAT 경로가 강제되고, 이 경로가 쓰는 `__flush_tlb()`와
  `__write_cr4()`는 5.10에서 모듈이 사용할 수 없습니다. `build-nvidia.sh`가 둘 다
  치환하지만 *위치*가 바뀝니다 — 550 이하는 CR4 쓰기를 `common/inc/nv-linux.h`에 두었고,
  580은 `nvidia/nv-pat.c`에서 다른 인자 형태로 직접 호출합니다. 그래서 패처는 트리를
  탐색하며, **호출부가 하나라도 남으면 빌드를 중단합니다** — 조용히 건너뛴 패치는 예전에
  무관해 보이는 `native_write_cr4 undefined` modpost 에러로만 드러났기 때문입니다.
- R515+ 브랜치는 Turing 이상에서 **GSP 펌웨어**를 로드합니다. 공식 `.run`에서
  추출했으며(`gsp_tu10x.bin` + `gsp_ga10x.bin`만 존재 — Ada/Blackwell용 blob은
  없음), `nv-gsp-<ver>.tgz`로 패키징해 `install.sh`가 커널 모듈 로드 **전에**
  `/lib/firmware/nvidia/<ver>/`에 배치합니다(GSP는 probe 시점에
  `request_firmware()`로 요청되므로 순서가 중요합니다). `/lib/firmware`는 다른
  파일들과 같은 rw 루트에 있어 재부팅 후에도 유지되고 재배치가 필요 없습니다.
  펌웨어가 없는 GSP 필요 GPU(Ada/Blackwell)는 여전히 `install.sh`의 경고
  게이트에 걸립니다.
  **한계: 다운로드/sha256/배치까지 단위 검증은 했으나, 실제 Turing/Ampere
  하드웨어로는 아직 검증하지 못했습니다** — 이번 세션에 접근 가능한 유일한
  박스가 Pascal GPU라 GSP 경로 자체가 스킵됩니다.

### 작업 규칙

소스 변경 → **여기서 먼저 commit/push** → VM에서 **`git pull`** → 그다음 빌드.
커밋되지 않은 로컬 변경으로는 절대 빌드하지 않습니다.

### 빌드 출처와 재현성

580 K5 EPYC7002/EPYC7003 비교에서는 절차상의 공백이 드러났습니다. GitHub Actions에서
Docker Desktop으로 빌드 환경을 바꾼 행위 자체가 잘못인 것은 아니지만, 임시 로컬 명령의
스크립트와 입력값을 커밋하거나 기록하지 않으면 나중에 결과를 정확히 비교하기 어렵습니다.
같은 컴파일러 이미지라는 사실만으로 두 빌드의 입력과 옵션까지 같았다고 볼 수 없습니다.
이번 조사에서는 과거 EPYC7002 성공 빌드의 명령·설정 기록이 충분하지 않아 EPYC7003과의
차이를 만든 단일 원인을 특정하지 못했습니다. 확보된 A/B 검사는 가능성을 좁혔지만 원인을
확정하지는 못했습니다.

앞으로 플랫폼 비교를 시작할 때는 성공한 파일럿 경로부터 보존한 뒤 매트릭스를 확장합니다.
Docker Desktop과 GitHub Actions는 동일한 버전 관리 빌드 스크립트를 호출하고, 플랫폼별
차이는 문서화된 명시적 설정으로 전달해야 합니다. 최소한 소스 커밋과 스크립트 해시,
컴파일러 이미지 digest, NVIDIA `.run` 해시, 플랫폼/커널 빌드 트리 및 `.config`와
`Module.symvers` 식별값, 전체 명령과 환경·옵션, 적용 패치, conftest 결과, 빌드 로그,
산출물 아카이브 해시와 모듈 메타데이터를 남깁니다. 이 기록으로 성공 경로를 재현하기 전에는
이를 기준 빌드 방식으로 간주하지 않습니다. 진단 산출물은 정규 릴리즈 자산과 분리하고,
검토를 마친 뒤에만 승격합니다.

</details>
