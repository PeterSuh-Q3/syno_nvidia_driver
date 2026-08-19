# syno_nvidia_driver SPK packages

Offline, one-click DSM Package Center installers for the no-auth NVIDIA
driver. Each `.spk` bundles the kernel modules, shared userspace, and (where
applicable) GSP firmware for its platform group — no network access is
needed during install. This is a companion artifact to the `nvidia` release
tag (raw `.tgz` layers + `install.sh`/`uninstall.sh`); the layers there
remain the source of truth these packages are built from.

## Which file do I need?

| File | Driver | Kernel | DSM | Platforms |
|---|---|---|---|---|
| `syno-nvidia-driver-kver5-580.173.02-1.spk` | 580.173.02 | 5.10.55 | 7.2+ | epyc7002, epyc7003, epyc7003ntb, geminilakenk, icelaked, r1000nk, v1000nk |
| `syno-nvidia-driver-kver4-dsm72-550.163.01-1-dsm7.2-7.4.spk` | 550.163.01 | 4.4.302 | 7.2 – 7.4 | apollolake, broadwell, broadwellnk, broadwellnkv2, broadwellntbap, geminilake, purley, r1000, v1000 |
| `syno-nvidia-driver-kver4-dsm70-550.163.01-1-dsm7.0-7.1.spk` | 550.163.01 | 4.4.180 | 7.0 – 7.1 | (same 9 platforms as above) |

Find your platform with `uname -a` — the token right after `synology_` is
the platform name (e.g. `synology_apollolake_ds218` → `apollolake`).

**Why three packages, not one universal installer?** The two kver4 packages
target the *same 9 platforms* but different DSM releases: DSM 7.0/7.1 ships
kernel 4.4.180 on these platforms, DSM 7.2+ moved them to 4.4.302 — same
platform name, different kernel `vermagic`, so the kernel module must match
exactly. DSM's own `os_min_ver` field can only express a floor, not a
ceiling, so a single package can't safely claim "7.0 only" vs "7.2+" —
hence two separate packages, with the DSM range spelled out in the filename.

**Why is 550.163.01 the ceiling on kver4 (4.4.x kernels)?** NVIDIA hard-blocks
driver 560 and newer from loading on kernels older than Linux 4.15 — DSM's
4.4.x kernels don't qualify. 550.163.01 is the newest branch that still
supports them.

**GSP firmware**: only the kver5/580.173.02 package bundles GSP firmware
(`gsp_tu10x.bin`, `gsp_ga10x.bin`) — that's the only branch/platform group
here running Turing/Ampere-class silicon that needs it via
`request_firmware()`. The 550-branch kver4 packages target older kernels
and don't require it.

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

## Verification

```
733f6f05fa083beab1604b6fc4678a332a4e756192ba6e4cb5d3e8e8a92ec8e2  syno-nvidia-driver-kver4-dsm70-550.163.01-1-dsm7.0-7.1.spk
0dd750e8f320607c37e4e7323cb12395f9205049f0d2e79d851fe00f4c8e10de  syno-nvidia-driver-kver4-dsm72-550.163.01-1-dsm7.2-7.4.spk
8debaaed900879dc18c581e65e7747fb06d499a6eeef5e0c38587ca3c3ef78a3  syno-nvidia-driver-kver5-580.173.02-1.spk
```

---

# syno_nvidia_driver SPK 패키지

DSM 패키지 센터에서 원클릭으로 설치하는 오프라인 무인증 NVIDIA 드라이버
패키지입니다. 각 `.spk`에는 해당 플랫폼 그룹의 커널 모듈, 공용 유저스페이스,
그리고 필요한 경우 GSP 펌웨어까지 모두 포함되어 있어 설치 중 네트워크 접속이
필요 없습니다. 이 패키지들은 `nvidia` 릴리즈 태그(원본 `.tgz` 레이어 +
`install.sh`/`uninstall.sh`)의 부속 산출물이며, 실제 빌드 원본은 여전히
그쪽 레이어입니다.

## 어떤 파일을 받아야 하는가?

| 파일 | 드라이버 | 커널 | DSM | 플랫폼 |
|---|---|---|---|---|
| `syno-nvidia-driver-kver5-580.173.02-1.spk` | 580.173.02 | 5.10.55 | 7.2+ | epyc7002, epyc7003, epyc7003ntb, geminilakenk, icelaked, r1000nk, v1000nk |
| `syno-nvidia-driver-kver4-dsm72-550.163.01-1-dsm7.2-7.4.spk` | 550.163.01 | 4.4.302 | 7.2 ~ 7.4 | apollolake, broadwell, broadwellnk, broadwellnkv2, broadwellntbap, geminilake, purley, r1000, v1000 |
| `syno-nvidia-driver-kver4-dsm70-550.163.01-1-dsm7.0-7.1.spk` | 550.163.01 | 4.4.180 | 7.0 ~ 7.1 | (위와 동일한 9개 플랫폼) |

내 플랫폼은 `uname -a` 실행 결과에서 `synology_` 바로 뒤 토큰으로 확인할 수
있습니다 (예: `synology_apollolake_ds218` → `apollolake`).

**왜 통합 설치본이 아니라 3개로 나눴는가?** kver4용 두 패키지는 *동일한
9개 플랫폼*을 대상으로 하지만 DSM 버전에 따라 커널이 다릅니다 — DSM 7.0/7.1은
이 플랫폼들에서 커널 4.4.180을, DSM 7.2+는 4.4.302를 사용합니다. 플랫폼명은
같아도 커널 `vermagic`이 다르므로 커널 모듈이 정확히 일치해야 합니다. DSM의
`os_min_ver` 필드는 하한선만 표현할 수 있고 상한선을 지정할 수 없어서, 패키지
하나로는 "7.0 전용"과 "7.2+ 전용"을 안전하게 구분할 수 없습니다. 그래서 두
패키지로 분리하고, 대상 DSM 버전 범위를 파일명에 명시했습니다.

**kver4(4.4.x 커널)는 왜 550.163.01이 상한인가?** NVIDIA는 드라이버 560 이상
버전에서 Linux 4.15보다 오래된 커널에서의 로드를 하드코딩으로 차단합니다.
DSM의 4.4.x 커널은 이 조건을 만족하지 못하므로, 이 커널들을 지원하는 가장
최신 브랜치인 550.163.01이 상한선입니다.

**GSP 펌웨어**: kver5/580.173.02 패키지에만 GSP 펌웨어(`gsp_tu10x.bin`,
`gsp_ga10x.bin`)가 포함되어 있습니다 — Turing/Ampere급 GPU가 `request_firmware()`
로 이 펌웨어를 요구하는 유일한 브랜치/플랫폼 그룹이기 때문입니다. 550 브랜치
kver4 패키지들은 더 오래된 커널을 대상으로 하며 GSP가 필요 없습니다.

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

## 검증

```
733f6f05fa083beab1604b6fc4678a332a4e756192ba6e4cb5d3e8e8a92ec8e2  syno-nvidia-driver-kver4-dsm70-550.163.01-1-dsm7.0-7.1.spk
0dd750e8f320607c37e4e7323cb12395f9205049f0d2e79d851fe00f4c8e10de  syno-nvidia-driver-kver4-dsm72-550.163.01-1-dsm7.2-7.4.spk
8debaaed900879dc18c581e65e7747fb06d499a6eeef5e0c38587ca3c3ef78a3  syno-nvidia-driver-kver5-580.173.02-1.spk
```
