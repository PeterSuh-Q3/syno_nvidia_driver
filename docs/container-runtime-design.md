# NVIDIA 컨테이너 런타임 설계서 (진행 문서)

> 2026-07-29 작성. Container Manager(Docker) 안에서 우리 드라이버의 GPU 를
> 컨테이너가 쓸 수 있게 하는 작업의 환경 조사, pdbear 방식과의 비교, 빌드/배포
> 설계, 미해결 리스크를 기록한다.

## 1. 문제 정의

지금까지 만든 `nvidiadriver`(호스트 커널 모듈 + userspace)는 DSM 자체에서
`nvidia-smi`가 뜨고 Plex/Jellyfin 이 NVENC 를 쓰는 데까지만 해결한다. 이번
과제는 그 위에서 **Container Manager(Docker)로 띄운 컨테이너**가 같은 GPU 를
쓸 수 있게 하는 것 — 즉 Ollama/vLLM/PyTorch 같은 AI 컨테이너를 겨냥한다.

Docker 컨테이너는 기본적으로 호스트의 `/dev/nvidia*` 를 보지 못한다. 표준
해법은 NVIDIA Container Toolkit 이 제공하는 **런타임 후크**로, 컨테이너
시작 시점에 필요한 디바이스 노드와 라이브러리를 자동으로 주입한다. 이걸 DSM
에 들여오는 것이 이번 설계의 목표다.

## 2. 실측 환경 조사 (박스 89, 2026-07-29)

| 항목 | 값 | 설계에 미치는 영향 |
|---|---|---|
| Docker (Container Manager) | **24.0.2**, API 1.43 | **CDI 네이티브 지원은 25+ 부터** → 이 DSM 버전에서는 선택지가 아님(§3) |
| 등록된 런타임 | `runc`, `io.containerd.runc.v2` (default: runc) | 여기에 `nvidia` 런타임을 새로 등록해야 함 |
| daemon.json 실체 경로 | `/var/packages/ContainerManager/etc/dockerd.json` | 패키지 관리 파일 — 직접 쓰기는 가능함을 실측(§5), 영속성은 별도 리스크 |
| runc 실체 경로 | `/var/packages/ContainerManager/target/usr/bin/runc` (심볼릭 링크 경유) | 셔임이 감쌀 대상의 정확한 위치 |
| Cgroup | **v1**, driver `cgroupfs` | `libnvidia-container` 의 cgroup 디바이스 화이트리스팅 경로(§7 리스크) |
| Storage driver | btrfs | 무관 |
| glibc | **2.36** | CentOS7 대상 prebuilt 바이너리와 하위호환 방향이라 문제 없음(§4) |
| 커널 | 5.10.55+ (kver5, 우리 기존 빌드 대상과 동일) | — |
| Docker 버전 업그레이드 가능 여부 | **불가** — Synology 가 Container Manager 패키지에 통째로 고정 배포. 최신판(24.0.2-1606)이 현재 최고 버전 | CDI 경로를 원천 배제하는 결정적 사실 |

## 3. 선택지 비교: CDI vs 런타임 셔임

두 갈래가 있고, **Docker 버전이 갈림길을 강제로 결정한다.**

| | CDI (`--device nvidia.com/gpu=all`) | 런타임 셔임 (`nvidia-container-runtime`) |
|---|---|---|
| 요구 사항 | Docker **25+** | Docker 어떤 버전이든 (오래전부터 지원) |
| daemon.json 변경 | 불필요 (CLI 플래그만) | **필요** — `runtimes.nvidia` 등록 |
| 우리 DSM(24.0.2) | ❌ 불가 | ✅ 가능 |

→ **런타임 셔임 방식으로 확정.** CDI 는 Docker 25 가 배포되기 전까지는 이 논의에서 제외한다(재검토 트리거: Synology 가 Container Manager 를 25+ 로 올릴 때).

## 4. 빌드 vs 재사용 — libnvidia-container 를 직접 빌드할 필요가 있는가?

결론: **없다.** upstream 이 배포하는 사전빌드 바이너리를 그대로 쓸 수 있다.

NVIDIA 공식 릴리즈(`nvidia-container-toolkit` v1.19.1)의 `rpm_x86_64` 패키지를
받아 실제로 까본 결과:

```
release-v1.19.1-stable/packages/centos7/x86_64/
  nvidia-container-toolkit-1.19.1-1.x86_64.rpm       (CLI 래퍼)
  nvidia-container-toolkit-base-1.19.1-1.x86_64.rpm  (nvidia-ctk, nvidia-cdi-hook)
  libnvidia-container1-1.19.1-1.x86_64.rpm           (핵심 .so)
  libnvidia-container-tools-1.19.1-1.x86_64.rpm      (nvidia-container-cli)
```

추출된 실행물:

```
usr/bin/nvidia-container-cli
usr/bin/nvidia-container-runtime
usr/bin/nvidia-container-runtime-hook
usr/bin/nvidia-ctk
usr/bin/nvidia-cdi-hook          # (CDI 는 미사용이지만 같이 딸려옴)
usr/lib64/libnvidia-container.so.1.19.1
usr/lib64/libnvidia-container-go.so.1.19.1
```

**대상이 CentOS7**(`for GNU/Linux 2.6.32` ELF 인터프리터 태그)이라는 게
핵심이다 — glibc/커널 ABI 기준이 매우 낮게 잡혀 있어, 이보다 훨씬 신형인
DSM(glibc 2.36, kernel 5.10)에서 **하위호환 방향**으로 문제없이 동작할
가능성이 높다. 이는 우리가 지금까지 NVIDIA `.run` 드라이버의 오픈 glue 만
재컴파일해온 것과 원리가 같다 — 다만 이번엔 재컴파일조차 필요 없다.

### 4-1. 동적 링크 의존성 실측

```
nvidia-container-cli    -> libnvidia-container.so.1, libdl.so.2, libcap.so.2, libc.so.6
libnvidia-container.so  -> libdl.so.2, libcap.so.2, libpthread.so.0, libelf.so.1,
                            libseccomp.so.2, libc.so.6
```

박스 89에서 실제로 대조한 결과:

| 라이브러리 | DSM 에 있는가 |
|---|:---:|
| `libcap.so.2` | ✅ `/usr/lib/libcap.so.2` |
| `libdl.so.2` | ✅ |
| `libpthread.so.0` | ✅ |
| **`libelf.so.1`** | ❌ 없음 |
| **`libseccomp.so.2`** | ❌ 없음 |

→ **2개만 동봉하면 된다.** 둘 다 CentOS7 vault 저장소에서 같은 세대의
바이너리를 그대로 구할 수 있어 ABI 불일치 위험이 없다:
`elfutils-libelf-0.176-5.el7.x86_64.rpm`, `libseccomp-2.3.1-4.el7.x86_64.rpm`
(둘 다 LGPL — 무수정 재배포 가능, LICENSE 동봉 예정).

`libnvidia-container-libseccomp2` 서브패키지는 실제 라이브러리를 담고 있지
않고 라이선스 파일뿐인 메타패키지임을 확인했다(distro 의존성 선언용) — 그래서
CentOS7 vault 쪽 실물이 필요하다.

## 5. daemon.json — pdbear 방식과 우리 방식 비교

pdbear(`syno_nvidia_gpu_driver`)의 Docker 연동은 **daemon.json 수정 + Simple
Permission Manager(SPM)** 조합이다. 이걸 그대로 따라야 하는지가 이번 지시의
핵심 질문이므로 구조부터 분석한다.

### 5-1. SPM 이 실제로 하는 일

`XPEnology-Community/SimplePermissionManager` 는 DSM 패키지들이 **설치 후
지속적으로 실행되는 상태에서** 권한이 필요한 명령을 실행할 수 있게 해주는
브로커다. 핵심은 `/usr/local/bin/spm-exec`:

```
spm-exec /path/to/script.sh          # 지정된 스크립트를 상승된 권한으로 실행
spm-exec -pid /path/to/pid script.sh
```

동작 방식: 패키지가 `spm-exec`를 통해 실행을 **요청**하면, 사용자가 SPM 의
DSM UI(Package 탭 / Users 탭)에서 **그 패키지·그 사용자**를 화이트리스트에
올려야 승인된다. pdbear 의 설치 가이드도 이 순서를 그대로 요구한다 — SPM
설치 → 드라이버 패키지 설치 → SPM 의 Users 탭에서 `NVIDIARuntimeLibrary` 를
찾아 체크 → 드라이버 재시작.

### 5-2. SPM 이 필요한 이유 — pdbear 의 배포 형태 때문

pdbear 는 **Package Center 로 설치하는 정식 `.spk` 패키지**를 배포한다. DSM
의 패키지 보안 모델에서 (특히 서명된 패키지는) 설치된 패키지가 **자기
자신의 계정으로, 재부팅마다, 무인(unattended) 상태로** 반복해서 root 수준
동작(커널 모듈 재적재, `/dev` 노드 재생성, docker daemon.json 수정 등)을
하려면 별도의 승인 경로가 필요하다. SPM 은 정확히 이 틈 —
**"사람이 곁에 없어도 특정 root 작업을 반복 수행해야 하는 상시 패키지"**
— 를 메우는 도구다.

### 5-3. 우리 아키텍처는 이 틈이 원천적으로 없다

우리는 pdbear 와 배포 형태 자체가 다르다:

| | pdbear | 우리 |
|---|---|---|
| 배포 형태 | Package Center `.spk` (상시 실행 패키지) | ① redpill-load 부팅 훅(addon) ② `curl \| sudo bash` 단발 설치기 |
| root 실행 시점 | 설치 후에도 **계속, 무인으로** | ① 부팅 시 1회 ② 사용자가 호출할 때 1회 |
| root 권한 확보 방식 | DSM 패키지 샌드박스 안 → SPM 브로커 필요 | 이미 root 컨텍스트에서 실행 → 브로커 불필요 |

구체적으로:

- **①(loader 부팅 훅)** 은 `redpill-load` 의 `on_patches`/`on_os_load` 단계에서
  실행된다. 이건 DSM 의 패키지 보안 모델이 적용되는 시점보다 **훨씬 이전**,
  부팅 램디스크 처리 과정의 일부라 애초에 root 그 자체다. SPM 이 다루는
  "샌드박스된 패키지 계정"이라는 개념 자체가 없다.
- **②(install.sh)** 는 사용자가 `sudo bash` 로 **직접, 대화형으로** 실행한다.
  이미 최상위 권한으로 시작하므로 승인 절차가 필요 없다.

즉 **SPM 이 푸는 문제 자체가 우리에게는 존재하지 않는다.** SPM 을 들여오면
- 사용자에게 서드파티 커뮤니티 패키지 설치를 하나 더 강제하고
- "패키지 탭에서 체크박스 켜기"라는 수동 단계를 추가하고
- 우리 배포 모델(무인증, 최소 의존성)의 단순함을 해치면서도
- 실질적으로 해결해주는 문제가 없다.

**결론: SPM 은 채택하지 않는다.** daemon.json 수정과 런타임 등록은 우리의
기존 `install.sh`(1회, root) 또는 향후 만들 boot hook(부팅 시, 이미 root)
에서 직접 수행하면 충분하다 — pdbear 가 그 경로를 SPM 으로 우회한 것은
그들이 SPK 배포 형태를 택했기 때문이지, daemon.json 수정 자체가 SPM 을
요구하는 것이 아니다.

### 5-4. daemon.json 쓰기 실측 결과

박스 89에서 `/var/packages/ContainerManager/etc/dockerd.json` 에 테스트
마커를 직접 기록 → Container Manager 패키지를 정지/재기동 → 마커가 그대로
남아있음을 확인했다. **root 로 직접 쓰기가 가능하다.**

다만 재기동 도중 `synopkg status` 가 계속 `"stop"` 으로 보고되는 현상을
관측했다(`docker ps`/`docker run hello-world` 는 정상 동작함에도). DSM 자체
상태 점검 스크립트의 이상으로 보이나, **daemon.json 을 건드리는 방식이 DSM
의 패키지 상태 판정에 영향을 줄 수 있다는 신호**로 간주해 §7 리스크에 남긴다.

## 6. 제안 설계

### 6-1. 레이어 구성 (기존 2층 패키징과 같은 원칙)

```
nv-container-runtime-<toolkit_ver>.tgz   (플랫폼 무관, x86_64 공통, 커널 무관)
  usr/bin/{nvidia-container-cli,nvidia-container-runtime,
           nvidia-container-runtime-hook,nvidia-ctk}
  usr/lib64/libnvidia-container.so.1.<ver>
  usr/lib64/libnvidia-container-go.so.1.<ver>
  usr/lib64/libelf.so.1        # CentOS7 vault 에서 동봉
  usr/lib64/libseccomp.so.2    # CentOS7 vault 에서 동봉
```

기존 `nv-ko-*`/`nv-userspace-*` 와 달리 **커널·플랫폼 완전 무관** — 드라이버
설치 여부와 별개로 한 번만 빌드하면 전 플랫폼·전 드라이버 버전에서
재사용된다. `nvidia-index.json` 에 최상위 키(`container_runtime`)로
별도 관리하는 편이 자연스럽다(플랫폼/드라이버 매트릭스에 종속시키지 않음).

### 6-2. 배치 대상

```
/usr/local/nvidia-runtime/{bin,lib}/     # 우리 드라이버와 같은 규칙(/usr/local/nvidia 옆)
/etc/nvidia-container-runtime/config.toml  # nvidia-container-cli 설정
```

### 6-3. daemon.json 통합

```json
{
  "runtimes": {
    "nvidia": {
      "path": "/usr/local/nvidia-runtime/bin/nvidia-container-runtime",
      "runtimeArgs": []
    }
  }
}
```

`/var/packages/ContainerManager/etc/dockerd.json` 은 이미 값이 들어있는
파일이므로 **덮어쓰기가 아니라 JSON 병합**으로 처리해야 한다(우리
`merged-addons.json` 에서 이미 쓰던 것과 같은 패턴 — jq 로 기존 키 보존 +
`runtimes.nvidia` 만 추가).

### 6-4. install.sh 확장 지점

기존 8단계 뒤에 선택 단계로 추가하는 안:

```
Step 9 (optional)  Container Manager 연동
  - Container Manager 설치 여부 감지 (/var/packages/ContainerManager 존재?)
  - 감지 시: "컨테이너에서도 이 GPU 를 쓰시겠습니까? [y/N]"
  - y 선택 시: 런타임 레이어 다운로드·배치 → daemon.json 병합
    → Container Manager 재시작(synopkg restart ContainerManager)
```

Plex/Jellyfin 재시작 안내와 같은 원칙 — **패키지를 건드렸으면 재시작까지
안내**한다.

## 7. 미해결 리스크 (다음 세션에서 검증할 것)

1. **daemon.json 영속성.** 이번 실측은 "패키지 재시작"까지만 확인했다.
   **Container Manager 자체 업데이트**(버전업)가 이 파일을 초기화하는지는
   미검증 — 검증 전까지는 boot hook 에서 매 부팅 시 재확인/재병합하는
   방어적 설계를 기본값으로 잡는다.
2. **cgroup v1 호환성.** 박스 89는 `cgroupfs` + **cgroup v1** 이다.
   `nvidia-container-cli` 의 디바이스 화이트리스팅이 v1 경로에서 문제없이
   동작하는지 실제 컨테이너 실행으로 확인 필요(예: 최신
   nvidia-container-toolkit 이 v1 디바이스 cgroup 처리를 얼마나 우선
   지원하는지는 버전마다 달라질 수 있음).
3. **`synopkg status` 이상 현상.** daemon.json 을 직접 편집한 뒤 DSM 이
   패키지를 "stop" 으로 오판했다(§5-4). 원인이 우리 편집 때문인지, 이
   테스트 환경 고유의 문제인지 재현·격리 필요.
4. **CentOS7 바이너리의 실제 DSM 실행 검증.** 지금까지는 정적 분석(file/
   objdump)만 했다 — 실제로 박스에 올려 `nvidia-container-cli info` 정도는
   돌려봐야 한다.
5. **Container Manager 미설치 사용자.** 감지 실패 시 조용히 스킵하고,
   나중에 Container Manager 를 설치한 사용자를 위한 재실행 경로(예:
   `install.sh --runtime-only`) 를 고려.

## 8. 다음 단계

1. §7-4 실제 실행 검증 (박스 89: CentOS7 바이너리 + 동봉 libelf/libseccomp
   으로 `nvidia-container-cli info` 성공 여부)
2. 검증 성공 시: 레이어 tgz 빌드 → Release 업로드 → `nvidia-index.json`
   최상위 `container_runtime` 키 등록
3. `install.sh` Step 9(선택) 구현 + daemon.json jq 병합 로직
4. 실제 컨테이너(`nvidia/cuda:12.9-base` 등)로 `docker run --runtime=nvidia
   --gpus all nvidia-smi` 성공까지 확인 후 릴리즈
