# NVIDIA 580 브랜치 도입 설계서 (진행 문서)

> 2026-07-28 작성. SA6400(epyc7002) / DSM 7.4 / kernel 5.10.55 대상 580 드라이버
> 빌드 작업의 배경 조사, 구현 현황, 첫 빌드 실패 상태, 그리고 다른 PC에서
> 이어서 진행할 절차를 기록한다.

## 1. 배경 조사 결과 (2026-07-28 웹 검증 완료)

### 드라이버 브랜치 ↔ CUDA 매핑

| 브랜치 | 네이티브 CUDA | 상태 | 비고 |
|---|---|---|---|
| 550.163.01 (현 트랙) | 12.4 | R550 최종본(2025-04-17), **EOL** | 보안 패치 종료 |
| 570.x | 12.8 | | Pascal 지원 |
| 575.x | 12.9 | | **Pascal용 실질 최고 CUDA** |
| **580.x** | **13.0** | **레거시 브랜치로 유지보수 중** | **Maxwell/Pascal/Volta~Blackwell(RTX 50) 전 세대를 커버하는 마지막 브랜치** |
| 590/595.x | 13.1/13.2 | 현행 | **Turing 미만 삭제** — P620/GTX 1060 불가, open kernel module + GSP 펌웨어 표준 |

### 핵심 사실

- **커널 요구사항**: 580의 최소 커널은 4.15+ (공식 README) → **5.10.55 빌드 공식 지원 범위**.
  glibc 2.11+ → DSM 7.x 문제없음.
- **CUDA 13.0은 Pascal 제거**: 툴킷 13.0부터 sm_75(Turing) 미만 완전 삭제.
  Pascal(P620, GTX 1060 = sm_61)의 CUDA 상한은 드라이버와 무관하게 **12.9**
  (12.9 실행에는 드라이버 ≥575 필요 → 580이면 충족).
- CUDA 13.x minor compatibility: 13.1/13.2 앱도 대부분 드라이버 ≥580.65.06에서 실행 가능.
- **Pascal은 proprietary 커널 모듈 필수** (open module은 Turing+ 전용).
  → 기존 빌드 방식(kernel/ glue + nv-kernel blob 재링크) 유지가 맞음. kernel-open/ 금지.
- Turing+ GPU는 580에서 GSP 펌웨어(`gsp_*.bin`) 사용 → 펌웨어 동봉 필요(향후 install.sh 작업).
- 전략 결정: **580.x를 메인 트랙으로 추가** (Pascal~Blackwell 단일 커버).
  595는 Turing+ 전용 별도 트랙으로 추후 검토(빌드 방식이 open-module 전체 소스 빌드로 달라짐).
- 검증된 리소스:
  - `.run` URL 유효(HTTP 200): `https://us.download.nvidia.com/XFree86/Linux-x86_64/580.159.03/NVIDIA-Linux-x86_64-580.159.03.run`
    (580.65.06 / .76.05 / .82.09 / .95.05 / .105.08 / .159.03 모두 200 확인, 580.126.14는 404)
  - Docker Hub `dante90/syno-compiler` 태그: 7.0~7.4, 6.2, latest 존재 확인.

## 2. 구현 현황

- 커밋 `d123cca`: [`.github/workflows/build-nvidia-580.yml`](../.github/workflows/build-nvidia-580.yml) 추가.
  - `workflow_dispatch` 입력: `driver_ver`(기본 580.159.03) / `platform`(epyc7002) /
    `dsm_ver`(7.4) / `kver`(5.10.55) / `upload_release`(기본 false)
  - 플로우: `.run` 다운로드 → `dante90/syno-compiler:<dsm_ver>` 컨테이너에서
    기존 `build-nvidia.sh` 실행(run-on-vm.sh와 동일) → GSP 펌웨어 tgz 추가 패키징 →
    잡 서머리에 nvidia-index.json fragment + sha256 → Actions artifact 업로드 →
    (옵션) `nvidia` Release 업로드.
  - `build-nvidia.sh`는 **무수정** — 550까지 검증된 스크립트 그대로 사용.

## 3. 첫 빌드 실패 (미해결 — 여기서부터 이어서 진행)

- Run: `build-nvidia-580 #1` (run id `30327983732`, job id `90177246744`, 2026-07-28 04:10 UTC)
- 결과: **"Build 2-layer package inside syno-compiler" 스텝에서 exit code 2 실패**.
  다운로드 스텝은 성공(= .run 확보는 정상), 이후 스텝은 모두 skip.
- **상세 로그 미확보**: Actions 로그는 로그인 필요. 비로그인 Annotation에는
  "Process completed with exit code 2"만 노출. 4m42s 소요 후 실패이므로
  다운로드(~수십초) + 추출 + conftest/컴파일 도중 사망으로 추정 —
  **원인 분석에는 전체 빌드 로그가 필수**.

### 예상 원인 후보 (로그 확보 후 검증할 것)

1. 550→580 사이 kernel glue 변화로 5.10 + Syno 커널 config에서 conftest/컴파일 오류
   (예: `nv-pat.c` 관련 패치 대상 코드 변경 — build-nvidia.sh의 sed는 조건부라
   580에서 패턴이 바뀌면 조용히 미적용됨).
2. 컨테이너 gcc 버전 vs 580 kbuild 요구사항 충돌.
3. `make modules` 병렬 빌드 중 특정 오브젝트 실패 (nvidia-drm/modeset 쪽 conftest).
4. (가능성 낮음) 러너 디스크 부족 — .run 400MB + 추출 + 빌드.

## 4. 다음 단계 (다른 PC에서 재개 절차)

1. **로그 확보** — 둘 중 하나:
   - GitHub 로그인 브라우저에서 run #1 → build 잡 → 실패 스텝 로그 확인, 또는
   - `gh` CLI: `gh run view 30327983732 -R PeterSuh-Q3/syno_nvidia_driver --log-failed`
2. **로컬 재현** (x86_64 + Docker 필요; 러너와 동일 환경):
   ```bash
   git clone git@github.com:PeterSuh-Q3/syno_nvidia_driver.git && cd syno_nvidia_driver
   mkdir -p run out
   curl -fL -o run/NVIDIA-Linux-x86_64-580.159.03.run \
     https://us.download.nvidia.com/XFree86/Linux-x86_64/580.159.03/NVIDIA-Linux-x86_64-580.159.03.run
   docker run --rm -t -u 0 -v "$PWD":/work dante90/syno-compiler:7.4 \
     bash /work/build-nvidia.sh 580.159.03 epyc7002 5.10.55 2>&1 | tee build-580.log
   ```
3. 오류 원인에 따라 `build-nvidia.sh`에 580용 호환 패치 추가(기존 nv-pat 패치처럼
   조건부 sed 방식 유지) 또는 워크플로우 수정.
4. 로컬 빌드 성공 확인 후 push → **Actions 재실행으로 최종 검증** (기본값 그대로 Run workflow).
5. 성공 시 후속 작업:
   - `nvidia-index.json`에 580 항목 추가 + `nvidia` Release에 tgz 업로드
     (`upload_release=true` 재실행으로 자동화 가능).
   - `install.sh`에 580 선택지(4번) 추가.
   - Turing+ 지원 시 GSP 펌웨어 배치 로직(`/lib/firmware/nvidia/<ver>/`) 추가.
   - 안정화 후 EOL 트랙(535/550) 정리 검토.

## 5. 판단 근거 링크

- [NVIDIA 580.65.06 최소 요구사항](https://download.nvidia.com/XFree86/Linux-x86_64/580.65.06/README/minimumrequirements.html) — 커널 4.15+, glibc 2.11+
- [Phoronix — 580은 Maxwell/Pascal/Volta 마지막 브랜치](https://www.phoronix.com/news/NVIDIA-580-Linux-Driver-Last-HW)
- [Tom's Hardware — CUDA 13, Pascal 이하 제거](https://www.tomshardware.com/pc-components/gpus/nvidia-to-drop-cuda-support-for-maxwell-pascal-and-volta-gpus-with-the-next-major-toolkit-release)
- [Arch Linux — 590 드라이버 Pascal 이하 삭제, open module 전환](https://archlinux.org/news/nvidia-590-driver-drops-pascal-support-main-packages-switch-to-open-kernel-modules/)
- [GamingOnLinux — 580.159.03 릴리스 (RTX 5090 수정 포함)](https://www.gamingonlinux.com/2026/04/nvidia-580-159-03-driver-released-for-linux-with-some-essential-fixes/)
