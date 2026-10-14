# syno_nvidia_driver SPK packages

Offline, one-click DSM Package Center installers for the NVIDIA
driver. Each `.spk` bundles the kernel modules, shared userspace, and (where
applicable) GSP firmware for its platform group — no network access is
needed during install. This is a companion artifact to the `nvidia` release
tag (raw `.tgz` layers + `install.sh`/`uninstall.sh`); the layers there
remain the source of truth these packages are built from.

## Which file do I need?

| File | Driver | Kernel | DSM | Platforms |
|---|---|---|---|---|
| `syno-nvidia-driver-kver5-580-proprietary-580.173.02-1.spk` | 580.173.02 proprietary | 5.10.55 | 7.2+ | epyc7002, epyc7003, geminilakenk, icelaked, r1000nk, v1000nk |
| `syno-nvidia-driver-kver5-580-open-580.173.02-1.spk` | 580.173.02 open | 5.10.55 | 7.2+ | epyc7002, epyc7003, geminilakenk, icelaked, r1000nk, v1000nk |
| `syno-nvidia-driver-kver5-595-proprietary-595.99.02-1.spk` | 595.99.02 proprietary | 5.10.55 | 7.2+ | epyc7002, epyc7003, geminilakenk, icelaked, r1000nk, v1000nk |
| `syno-nvidia-driver-kver5-595-open-595.99.02-1.spk` | 595.99.02 open | 5.10.55 | 7.2+ | epyc7002, epyc7003, geminilakenk, icelaked, r1000nk, v1000nk |
| `syno-nvidia-driver-kver4-dsm72-550.163.01-4-dsm7.2-7.4.spk` | 550.163.01 proprietary | 4.4.302 | 7.2 – 7.4 | apollolake, broadwell, broadwellnk, broadwellnkv2, broadwellntbap, geminilake, purley, r1000, v1000 |
| `syno-nvidia-driver-kver4-dsm70-550.163.01-4-dsm7.0-7.1.spk` | 550.163.01 proprietary | 4.4.180 | 7.0 – 7.1 | (same 9 platforms as above) |

## Open vs. proprietary kernel-module flavor

For K5 packages, **open** and **proprietary** identify the kernel-module
implementation only. Both use the same versioned NVIDIA proprietary user-space
stack for a given driver branch. The flavor alone does not add codec support or
promise a performance difference; the package's bundled GPU table is
authoritative for exact GPU-ID compatibility.

- **Open**: NVIDIA's dual MIT/GPL-licensed kernel modules, supported on Turing
  and newer GPUs. The 580 open package is limited to Turing/Ampere GPUs listed
  in its bundled table; 595 open supports the Turing-and-newer GPU IDs listed
  in its table.
- **Proprietary**: NVIDIA's traditional closed-source kernel modules. The 580
  proprietary package supports listed Maxwell-through-Ampere GPUs; 595
  proprietary supports listed Turing-and-newer GPUs. The K4 550 packages also
  use proprietary modules.

**Choosing a package:** check the GPU generation and exact PCI ID against the
package's bundled compatibility table. For Maxwell/Pascal/Volta, choose 580
proprietary when listed. For Turing or newer, compare the 580/595 tables. Choose
open when your exact GPU is listed there and you prefer NVIDIA's open
kernel-module implementation. Choose proprietary when your GPU is listed for
that flavor but not for open, or when you explicitly prefer the traditional
closed kernel module. The pre-install check rejects unsupported
GPU/branch/flavor combinations. Keep the kernel module, user-space stack, and
any required GSP firmware on the same driver version.

Find your platform with `uname -a` — the token right after `synology_` is
the platform name (e.g. `synology_apollolake_ds218` → `apollolake`).

**Why six packages, not one universal installer?** The four kver5 packages
cover the 580/595 driver branches and their open/proprietary kernel-module
flavors across the same six platforms. The two kver4 packages cover the same
nine platforms but different DSM kernel builds: DSM 7.0/7.1 uses kernel
4.4.180, while DSM 7.2–7.4 uses 4.4.302. Kernel modules must match the exact
kernel `vermagic`; the branch/flavor and kernel differences therefore require
separate packages. The platform list for each package is also explicit in its
DSM `arch` metadata and filename.

**Why is 550.163.01 the ceiling on kver4 (4.4.x kernels)?** NVIDIA hard-blocks
driver 560 and newer from loading on kernels older than Linux 4.15 — DSM's
4.4.x kernels don't qualify. 550.163.01 is the newest branch that still
supports them.

**GSP firmware**: all four kver5 packages (580/595, open/proprietary) bundle
the matching driver-version GSP firmware for GPUs that require it. The two
550-branch kver4 packages do not bundle GSP firmware.

## K5 upgrade and boot behavior

**Reboot after a driver-version upgrade.** A running NVIDIA kernel module cannot
be safely replaced while applications may be using it. If the installed
userspace version differs from the loaded module, the package records that
activation is pending and refuses an unsafe live replacement. Reboot DSM before
starting NVIDIA workloads; the package activates the matching module at boot.

**GSP firmware staging.** For a GPU marked as requiring GSP in the bundled
compatibility table, the package copies its matching firmware into
`/lib/firmware/nvidia/<driver-version>/` before loading the module. For example,
an Ampere GPU on 595 uses
`/lib/firmware/nvidia/595.99.02/gsp_ga10x.bin`. Firmware, kernel modules, and
userspace must come from the same driver version.

**K5 module recovery.** On kernel 5.10.55 only, if RR/PML or another boot-time
loader step removes NVIDIA `.ko` files from `/usr/lib/modules`, the package
restores the modules for the detected platform from its immutable SPK payload
before attempting to load them. This recovery is not enabled for K4 packages.

## What's actually inside

Each package is a standard DSM `.spk` — `INFO` + `package.tgz` + lifecycle
scripts (`postinst`/`preuninst`/`preupgrade`/`postupgrade`/
`start-stop-status`), all sourced from [`spk/`](../spk) in this repo and
assembled by [`scripts/build-spk.sh`](../scripts/build-spk.sh). Inside
`package.tgz`:

- `lib/modules/<platform>/*.ko` — the platform's kernel modules for this
  variant's exact kernel/driver combination
- `lib/nvidia/{bin,lib}` — shared userspace (nvidia-smi, libraries), staged
  to `/usr/local/nvidia` and `/usr/lib` at install time
- `lib/firmware/*.bin` — GSP firmware (kver5 package only)
- `share/nvidia-gpu-support.json` — offline copy of the GPU ID → arch/GSP
  requirement table, pinned to a fixed `tcrp-addons` commit so a package
  built today resolves the same table as one built after a future update

There is no persistent daemon: `start-stop-status`'s `start` action (which
DSM invokes at every boot regardless of the Package Center Start/Stop
buttons) inserts the kernel modules, creates `/dev/nvidia*` nodes, and
idempotently re-asserts Container Manager / Jellyfin integration if those
optional layers are present. Uninstalling cleanly reverses every change
(`preuninst`), including restoring Jellyfin's `service-setup` from the
backup taken before it was ever patched.

## ⚠️ Security fix (this build) — update if you installed an earlier `.spk`

Earlier builds' `postinst` copied the ~450MB shared userspace tree into
`/usr/local/nvidia` on every install. Two problems, now both fixed:

1. **System-partition duplication.** The SPK's own copy already lives on
   the data volume (`/volume1/@appstore/<pkg>/...`); the `cp` duplicated
   it onto the system partition (`/dev/md0`) for no reason — the exact
   space problem the `.spk` packaging exists to avoid (see the standalone
   `install.sh` complaints in
   [#7](https://github.com/PeterSuh-Q3/syno_nvidia_driver/issues/7)).
   `/usr/local/nvidia` is now a symlink straight into the package
   payload; confirmed on real hardware that install no longer grows
   `/dev/md0` by ~450MB.

2. **Privilege escalation.** That payload is owned by this package's own
   *unprivileged* service account — DSM's `conf/privilege` `tool` section
   only grants root ownership to individual file paths, not directories,
   so there was no way to get the ~100 userspace files root-owned at
   install time. Once `/usr/local/nvidia` became a symlink into that
   tree, every consumer on the box (Plex, Jellyfin, anything
   `dlopen()`-ing via `/usr/lib`) started loading directly from
   service-account-owned files — which meant that account could plant a
   trojaned `.so` and have it loaded into a root or other-user process.
   Fixed by re-locking the payload to `root:root` (parent directories
   included, not just the leaf files — delete-and-recreate is governed
   by the *parent's* write bit) on every privileged entry point
   (postinst **and** every boot), the same fix pattern
   [SynoSmartInfo v2.0.6](https://github.com/PeterSuh-Q3/SynoSmartInfo/releases/tag/v2.0.6)
   just applied for the identical class of bug
   ([issue #21](https://github.com/PeterSuh-Q3/SynoSmartInfo/issues/21)).

Verified on real hardware (DS1621+): confirmed the leaf-only chown left
the parent directory service-account-writable (attack still possible),
and that locking the parent closes it.

## Verification

```
48835f5a0ee5ed23389bd5b575dc2835ab7f82f4fac5eeb82193f99e7b546674  syno-nvidia-driver-kver5-580-proprietary-580.173.02-1.spk
4c53fbc087c6768d64453e2dde3974f172856386a1bfe6efe856684f87d66237  syno-nvidia-driver-kver5-580-open-580.173.02-1.spk
f221033e0e63f5db5e410b8e80bfa41ac5a24482863387e6f2ae3071acb872f2  syno-nvidia-driver-kver5-595-proprietary-595.99.02-1.spk
d7c0144b32d665a4779989869d23a0731db95b6e9417b97caf89a5fb6e7b819f  syno-nvidia-driver-kver5-595-open-595.99.02-1.spk
7f497d42fcfc88471f132afa551abe23f50f88d385bc1d216b5154f26828043c  syno-nvidia-driver-kver4-dsm70-550.163.01-4-dsm7.0-7.1.spk
da4fe2bcf6a4d0d9cfe5d69cdd1398d7df96a6978b1469861459a4a262b2231a  syno-nvidia-driver-kver4-dsm72-550.163.01-4-dsm7.2-7.4.spk
```

Verified end-to-end on real hardware (epyc7002/SA6400 + Quadro P1000):
`synopkg install` succeeds, all 4 NVIDIA kernel modules load, `nvidia-smi`
correctly reports the GPU. System-partition/ownership fix separately
verified on DS1621+ (v1000/kver4).

---

# syno_nvidia_driver SPK 패키지

DSM 패키지 센터에서 원클릭으로 설치하는 오프라인 NVIDIA 드라이버
패키지입니다. 각 `.spk`에는 해당 플랫폼 그룹의 커널 모듈, 공용 유저스페이스,
그리고 필요한 경우 GSP 펌웨어까지 모두 포함되어 있어 설치 중 네트워크 접속이
필요 없습니다. 이 패키지들은 `nvidia` 릴리즈 태그(원본 `.tgz` 레이어 +
`install.sh`/`uninstall.sh`)의 부속 산출물이며, 실제 빌드 원본은 여전히
그쪽 레이어입니다.

## 어떤 파일을 받아야 하는가?

| 파일 | 드라이버 | 커널 | DSM | 플랫폼 |
|---|---|---|---|---|
| `syno-nvidia-driver-kver5-580-proprietary-580.173.02-1.spk` | 580.173.02 proprietary | 5.10.55 | 7.2+ | epyc7002, epyc7003, geminilakenk, icelaked, r1000nk, v1000nk |
| `syno-nvidia-driver-kver5-580-open-580.173.02-1.spk` | 580.173.02 open | 5.10.55 | 7.2+ | epyc7002, epyc7003, geminilakenk, icelaked, r1000nk, v1000nk |
| `syno-nvidia-driver-kver5-595-proprietary-595.99.02-1.spk` | 595.99.02 proprietary | 5.10.55 | 7.2+ | epyc7002, epyc7003, geminilakenk, icelaked, r1000nk, v1000nk |
| `syno-nvidia-driver-kver5-595-open-595.99.02-1.spk` | 595.99.02 open | 5.10.55 | 7.2+ | epyc7002, epyc7003, geminilakenk, icelaked, r1000nk, v1000nk |
| `syno-nvidia-driver-kver4-dsm72-550.163.01-4-dsm7.2-7.4.spk` | 550.163.01 proprietary | 4.4.302 | 7.2 ~ 7.4 | apollolake, broadwell, broadwellnk, broadwellnkv2, broadwellntbap, geminilake, purley, r1000, v1000 |
| `syno-nvidia-driver-kver4-dsm70-550.163.01-4-dsm7.0-7.1.spk` | 550.163.01 proprietary | 4.4.180 | 7.0 ~ 7.1 | (위와 동일한 9개 플랫폼) |

## Open과 proprietary 커널 모듈 flavor

K5 패키지에서 **open**과 **proprietary**는 커널 모듈 구현 방식만 구분합니다.
같은 드라이버 브랜치라면 두 flavor 모두 동일 버전의 NVIDIA 비공개 사용자 공간
구성요소를 사용합니다. flavor만으로 코덱 지원이나 성능 차이가 생기지는 않으며,
패키지에 포함된 GPU 지원표가 정확한 GPU ID의 호환성을 결정합니다.

- **Open**: NVIDIA의 dual MIT/GPL 라이선스 커널 모듈이며 Turing 이상 GPU를
  대상으로 합니다. 580 open은 동봉된 표에 기재된 Turing/Ampere GPU를 지원하고,
  595 open은 동봉된 표의 Turing 이상 GPU ID를 지원합니다.
- **Proprietary**: NVIDIA의 기존 비공개 커널 모듈입니다. 580 proprietary는
  지원표의 Maxwell–Ampere GPU를, 595 proprietary는 지원표의 Turing 이상 GPU를
  지원합니다. K4 550 패키지도 proprietary 모듈을 사용합니다.

**선택 방법:** GPU 세대와 정확한 PCI ID가 패키지의 호환성 표에 포함되어 있는지
먼저 확인하세요. Maxwell/Pascal/Volta는 지원되는 경우 580 proprietary를
선택합니다. Turing 이상은 580/595 지원표를 비교하세요. 정확한 GPU ID가 open
지원표에 있고 공개 커널 모듈을 선호하면 open을 선택합니다. GPU가 proprietary
지원표에만 있거나 기존 비공개 커널 모듈을 선호하면 proprietary를 선택하세요.
설치 전 검사는 지원되지 않는 GPU/브랜치/flavor 조합을 차단합니다. 커널 모듈,
사용자 공간 구성요소, 필요한 GSP 펌웨어는 같은 드라이버 버전으로 맞춰야 합니다.

내 플랫폼은 `uname -a` 실행 결과에서 `synology_` 바로 뒤 토큰으로 확인할 수
있습니다 (예: `synology_apollolake_ds218` → `apollolake`).

**왜 통합 설치본이 아니라 6개로 나눴는가?** kver5용 네 패키지는 580/595
드라이버 브랜치와 open/proprietary 커널 모듈 flavor를 구분하며, 각 패키지는
동일한 6개 플랫폼을 지원합니다. kver4용 두 패키지는 동일한 9개 플랫폼을
대상으로 하지만 DSM 버전에 따라 커널이 다릅니다 — DSM 7.0/7.1은 4.4.180을,
DSM 7.2–7.4는 4.4.302를 사용합니다. 커널 모듈은 정확한 커널 `vermagic`과
일치해야 하므로 브랜치·flavor·커널 조합별로 패키지를 분리했습니다. 각 패키지의
지원 플랫폼은 파일명과 DSM `arch` 메타데이터에 명시되어 있습니다.

**kver4(4.4.x 커널)는 왜 550.163.01이 상한인가?** NVIDIA는 드라이버 560 이상
버전에서 Linux 4.15보다 오래된 커널에서의 로드를 하드코딩으로 차단합니다.
DSM의 4.4.x 커널은 이 조건을 만족하지 못하므로, 이 커널들을 지원하는 가장
최신 브랜치인 550.163.01이 상한선입니다.

**GSP 펌웨어**: kver5 패키지 네 종류(580/595, open/proprietary)는 해당 드라이버
버전과 일치하는 GSP 펌웨어를 포함합니다. 펌웨어는 이를 요구하는 GPU에서 사용됩니다.
550 브랜치의 kver4 패키지 두 종류에는 GSP 펌웨어가 포함되지 않습니다.

## K5 업그레이드 및 부팅 동작

**드라이버 버전 업그레이드 후 재부팅:** 애플리케이션이 사용 중일 수 있는 NVIDIA
커널 모듈은 실행 중 안전하게 교체할 수 없습니다. 설치된 사용자 공간 버전과 현재
로드된 모듈 버전이 다르면 패키지는 활성화 대기 상태를 기록하고, 위험한 실시간
교체를 하지 않습니다. NVIDIA 작업을 다시 시작하기 전에 DSM을 재부팅하면 부팅
과정에서 일치하는 모듈을 활성화합니다.

**GSP 펌웨어 배치:** 동봉된 호환성 표에서 GPU가 GSP를 요구한다고 표시된 경우,
패키지는 해당 드라이버 버전의 펌웨어를 모듈 로드 전에
`/lib/firmware/nvidia/<드라이버 버전>/`에 배치합니다. 예를 들어 595를 사용하는
Ampere GPU는 `/lib/firmware/nvidia/595.99.02/gsp_ga10x.bin`을 사용합니다.
펌웨어·커널 모듈·사용자 공간 구성요소는 동일한 드라이버 버전으로 맞춰야 합니다.

**K5 모듈 자동복원:** 커널 5.10.55에서만 RR/PML 또는 다른 부팅 단계가
`/usr/lib/modules`의 NVIDIA `.ko` 파일을 지운 경우, 패키지는 모듈 적재 전에
불변 SPK payload에서 현재 플랫폼에 맞는 모듈을 복원합니다. 이 복구 동작은 K4
패키지에는 적용되지 않습니다.

## 내부 구성

각 패키지는 표준 DSM `.spk` 형식(`INFO` + `package.tgz` + 생명주기 스크립트
`postinst`/`preuninst`/`preupgrade`/`postupgrade`/`start-stop-status`)이며,
전부 이 저장소의 [`spk/`](../spk) 디렉토리에서 관리되고
[`scripts/build-spk.sh`](../scripts/build-spk.sh)로 조립됩니다.
`package.tgz` 내부 구성:

- `lib/modules/<platform>/*.ko` — 해당 변형의 정확한 커널/드라이버 조합에
  맞는 플랫폼별 커널 모듈
- `lib/nvidia/{bin,lib}` — 공용 유저스페이스(nvidia-smi, 라이브러리 등),
  설치 시 `/usr/local/nvidia`와 `/usr/lib`에 배치됨
- `lib/firmware/*.bin` — GSP 펌웨어 (kver5 패키지에만 포함)
- `share/nvidia-gpu-support.json` — GPU ID → 아키텍처/GSP 필요 여부 테이블의
  오프라인 사본. `tcrp-addons`의 고정 커밋을 참조하므로, 오늘 빌드한
  패키지와 이후 테이블이 업데이트된 뒤 빌드한 패키지가 서로 다른 시점의
  값을 갖는 일이 없습니다.

상시 실행되는 데몬은 없습니다: DSM이 매 부팅 시(패키지 센터의 시작/중지
버튼 표시 여부와 무관하게) 호출하는 `start-stop-status`의 `start` 동작이
커널 모듈을 로드하고, `/dev/nvidia*` 노드를 생성하며, Container Manager /
Jellyfin 연동이 설치되어 있으면 멱등적으로 재적용합니다. 제거 시에는
`preuninst`가 모든 변경 사항을 깔끔하게 되돌립니다 — Jellyfin의
`service-setup`도 최초 패치 전 백업본으로 복원됩니다.

## ⚠️ 보안 수정 (이번 빌드) — 이전 `.spk`를 설치하셨다면 업데이트하세요

이전 빌드의 `postinst`는 매 설치마다 약 450MB짜리 공용 유저스페이스
전체를 `/usr/local/nvidia`에 복사했습니다. 이로 인한 문제 두 가지를
모두 이번 빌드에서 고쳤습니다.

1. **시스템 파티션 중복 사용.** SPK 자체의 사본은 이미 데이터 볼륨
   (`/volume1/@appstore/<pkg>/...`)에 있는데, `cp`가 그걸 시스템 파티션
   (`/dev/md0`)에 또 한 번 중복 배치하고 있었습니다 — `.spk` 패키징이
   애초에 피하려던 그 공간 문제([이슈 #7](https://github.com/PeterSuh-Q3/syno_nvidia_driver/issues/7)에
   보고된 스탠드얼론 `install.sh`의 문제)가 그대로 재현되고 있었던
   것입니다. `/usr/local/nvidia`는 이제 패키지 payload로 바로 향하는
   심볼릭 링크이며, 실기에서 설치 시 `/dev/md0` 사용량이 더 이상 450MB
   증가하지 않음을 확인했습니다.

2. **권한 상승 취약점.** 그 payload는 이 패키지 전용 **저권한 서비스
   계정** 소유입니다 — DSM의 `conf/privilege`의 `tool` 섹션은 개별
   파일 경로에만 root 소유권을 부여할 수 있고 디렉토리는 안 되므로,
   설치 시점에 약 100개의 유저스페이스 파일을 root 소유로 만들 방법이
   없었습니다. `/usr/local/nvidia`가 그 트리로 향하는 심볼릭 링크가
   되면서, Plex/Jellyfin 등 `/usr/lib`을 통해 `dlopen()`하는 모든
   소비자가 저권한 계정 소유 파일을 직접 로드하게 됐고, 그 계정이
   뚫리면 조작된 `.so`를 심어 root나 다른 계정 프로세스에 코드 실행을
   심을 수 있는 구조였습니다. `postinst`뿐 아니라 **매 부팅(`start`)마다**
   payload를(리프 파일만이 아니라 부모 디렉토리까지 — 삭제 후 재생성
   공격은 부모의 쓰기 비트로 결정되므로) `root:root`로 재잠금하도록
   고쳐서 해결했습니다. [SynoSmartInfo v2.0.6](https://github.com/PeterSuh-Q3/SynoSmartInfo/releases/tag/v2.0.6)이
   동일한 종류의 버그([이슈 #21](https://github.com/PeterSuh-Q3/SynoSmartInfo/issues/21))에
   적용한 것과 같은 수정 패턴입니다.

실기(DS1621+)에서 검증: 리프 파일만 `chown`했을 때는 부모 디렉토리가
여전히 서비스 계정 쓰기 가능 상태라 공격이 가능했고, 부모까지 잠그니
차단됨을 확인했습니다.

## 검증

```
48835f5a0ee5ed23389bd5b575dc2835ab7f82f4fac5eeb82193f99e7b546674  syno-nvidia-driver-kver5-580-proprietary-580.173.02-1.spk
4c53fbc087c6768d64453e2dde3974f172856386a1bfe6efe856684f87d66237  syno-nvidia-driver-kver5-580-open-580.173.02-1.spk
f221033e0e63f5db5e410b8e80bfa41ac5a24482863387e6f2ae3071acb872f2  syno-nvidia-driver-kver5-595-proprietary-595.99.02-1.spk
d7c0144b32d665a4779989869d23a0731db95b6e9417b97caf89a5fb6e7b819f  syno-nvidia-driver-kver5-595-open-595.99.02-1.spk
7f497d42fcfc88471f132afa551abe23f50f88d385bc1d216b5154f26828043c  syno-nvidia-driver-kver4-dsm70-550.163.01-4-dsm7.0-7.1.spk
da4fe2bcf6a4d0d9cfe5d69cdd1398d7df96a6978b1469861459a4a262b2231a  syno-nvidia-driver-kver4-dsm72-550.163.01-4-dsm7.2-7.4.spk
```

epyc7002(SA6400) + Quadro P1000 실기에서 end-to-end 검증 완료: `synopkg install`
성공, NVIDIA 커널 모듈 4개 전부 로드, `nvidia-smi`가 GPU를 정상 인식.
시스템 파티션/권한 수정은 DS1621+(v1000/kver4)에서 별도 검증.
