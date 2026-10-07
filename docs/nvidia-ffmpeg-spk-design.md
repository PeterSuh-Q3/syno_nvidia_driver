# NVIDIA FFmpeg 독립 SPK 설계

상태: 사이드 설계 (구현·빌드 전)

소유 저장소: `syno_nvidia_driver` — FFmpeg 패키지의 소스·빌드·릴리즈. 로더의 선택 및 전달 방식은 `tcrp-addons/nvidiadriver/docs/spk-delivery-design.md`를 따른다.

## 목적과 경계

기존 로더 메뉴의 `nvidia_ffmpeg` 선택을 더 이상 junior의 `nv-ffmpeg-<driver>.tgz` 주입으로 처리하지 않는다. 선택한 경우 독립 `syno-nvidia-ffmpeg` SPK를 DSM 부팅 후 내려받아 검증·설치한다. 드라이버 SPK와 필수 GPU Monitor SPK는 그대로 별개다. Plex는 자체 트랜스코더를 사용하므로 이 패키지가 필수는 아니다. 이 패키지의 주 대상은 **DSM에 직접 설치한 SynoCommunity Jellyfin**과 호스트 CLI 사용이며, Docker Jellyfin의 FFmpeg 파일을 자동 교체하지 않는다.

FFmpeg와 ffprobe를 한 SPK에 넣는다. 다른 패키지의 `target` 또는 `ffmpeg7` 파일을 덮지 않는다. 바이너리의 안정적인 경로는 `/var/packages/syno-nvidia-ffmpeg/target/bin/ffmpeg` 및 같은 디렉터리의 `ffprobe`로 한다. 별도 GSP 파일은 필요 없으며 GPU 커널 모듈과 사용자 공간 라이브러리는 통합 드라이버 SPK가 담당한다.

## 현재 구현에서 확인한 사실

- `make-ffmpeg-layer.sh`는 Jellyfin의 portable Linux x86_64 GPL 빌드에서 `ffmpeg`와 `ffprobe`를 추출하여 드라이버 버전별 `.tgz`를 만든다. 현재 원격 다운로드에 `curl -k`가 있고 원본 아카이브 해시를 고정하지 않는다. SPK 빌드 전에 출처·해시·라이선스 고지를 고정해야 한다.
- 릴리즈 `nvidia`에는 FFmpeg 계층이 `470.256.02`, `535.230.02`, `550.163.01`, `580.173.02`용으로만 있다. `595.99.02`용 계층은 **아직 없다**. 580 바이너리를 595와 자동으로 같은 것으로 취급하지 않는다.
- 현재 통합 드라이버 SPK의 `scripts/build-spk.sh`는 FFmpeg를 넣지 않는다. 반면 `spk/bin/nvidia-backend.sh`는 과거 주입 경로인 `/usr/local/nvidia/bin/ffmpeg`와 Jellyfin `service-setup`을 여전히 검사·수정하고, 드라이버 제거 시 `.pre-nvidia.bak`를 복원하려 한다. 이 설정의 소유권을 FFmpeg SPK로 옮기지 않으면 두 패키지가 같은 Jellyfin 파일을 서로 변경할 수 있다.
- SynoCommunity Jellyfin의 알려진 `service-setup`은 `--ffmpeg /var/packages/ffmpeg7/target/bin/ffmpeg`를 인자로 전달한다. 이 인자가 있을 때 Jellyfin UI의 FFmpeg 경로만 변경해서는 적용되지 않는다. DSM/Jellyfin 버전마다 파일·인자가 달라질 수 있으므로 정확한 패턴을 확인한 경우에만 수정한다.

## 패키지·버전 정책

패키지 ID는 `syno-nvidia-ffmpeg`, 아키텍처는 `x86_64`를 제안한다. `INFO`의 DSM 최소 버전은 실제 테스트 범위에 맞춰 정한다. 단일 FFmpeg 빌드가 여러 드라이버에서 검증되지 않았다면 **드라이버별 호환 자산**으로 나눈다. 같은 패키지 ID를 유지해 패키지 센터의 교체 설치가 가능하게 하고, SPK 버전은 대상 드라이버 버전과 패키지 개정 번호를 포함한다(예: `580.173.02-1`). `SOURCE`/메타데이터에는 Jellyfin FFmpeg의 정확한 태그, 원본 URL·SHA-256, FFmpeg 자체 버전·빌드 옵션, NVENC API 요구사항을 별도로 남긴다. 파일명만으로 호환성을 추정하지 않는다.

실제로 드라이버 SPK가 게시된 조합부터 시작한다.

| 드라이버 SPK | FFmpeg 후보 | 상태 |
|---|---|---|
| K4 `550.163.01` | 기존 `nv-ffmpeg-550.163.01.tgz`에서 재패키징 후보 | 바이너리·ffprobe·DSM 7.0–7.4 실기 검증 필요 |
| K5 `580.173.02` | 기존 `nv-ffmpeg-580.173.02.tgz`에서 재패키징 후보 | 바이너리·ffprobe·DSM 7.2+ 실기 검증 필요 |
| K5 `595.99.02` | 새로 고정 빌드하거나 580 후보와 **별도 호환 검증** | 검증된 자산을 게시하기 전까지 FFmpeg 선택을 설치 가능 항목으로 표시하지 않음 |

470/535 계층은 보존하지만 해당 버전의 통합 드라이버 SPK가 게시되지 않은 상태에서는 새 SPK 자동 설치 조합으로 광고하지 않는다. 한 바이너리가 580/595 모두에서 실제로 검증되면 추후 공통 자산 하나로 합칠 수 있다. 그때도 호환성 매니페스트와 테스트 결과를 먼저 갱신한다.

## 로더·DSM 설치 흐름

1. 기존 메뉴의 `nvidia_ffmpeg=true/false`를 선택 신호로 재사용한다. 메뉴는 **선택된 드라이버에 호환·게시된 FFmpeg SPK가 있을 때만** On을 허용한다. Auto 드라이버 선택일 때도 최종 드라이버가 정해지기 전에는 FFmpeg SPK를 추측하지 않는다. 조합이 불가하면 이유를 표시하고 FFmpeg 설치만 보류한다. 드라이버 및 필수 Monitor 설치 여부를 숨기거나 바꾸지 않는다.
2. 로더에는 선택 비트와 고정 매니페스트 항목만 넣는다. FFmpeg SPK를 initrd/junior `/tmp`에 담지 않는다. DSM의 영구 데이터 볼륨에 `.part`로 받고, 정확한 byte 수와 SHA-256, SPK `INFO`의 ID·버전·아키텍처를 검증한다. `curl -k` 또는 해시 검증 생략은 금지한다.
3. **드라이버 SPK 설치 및 활성 버전 확인 후** FFmpeg SPK를 설치한다. 활성 드라이버가 아직 이전 버전이면 재부팅 대기 상태로 두고 FFmpeg/Jellyfin 경로는 바꾸지 않는다. 동일한 FFmpeg SPK가 이미 설치됐다면 설치를 반복하지 않는다.
4. FFmpeg SPK 설치 자체와 Jellyfin 연동 상태는 분리한다. Jellyfin이 없으면 바이너리 설치만 성공으로 기록한다. Jellyfin이 있으면 인식한 서비스 인자 패턴이 정확히 일치할 때에만 자체 FFmpeg 경로로 바꾸고, 원본 파일·소유자·권한을 복구 가능하게 보존한다. 지원하지 않는 패턴이면 Jellyfin 파일은 변경하지 않고 `jellyfin_manual_setup_required`를 기록한다.
5. Jellyfin 설정을 변경했다면 필요할 때 **한 번만** Jellyfin을 재시작하고 정상 기동 여부를 확인한다. 실패하면 변경한 인자만 원상복구한다. `encoding.xml`의 사용자 설정은 덮지 않으며, 자동 HW 설정은 별도 명시 선택/기존 1회 스탬프 정책으로 다룬다. Jellyfin이 나중에 설치되거나 업데이트돼 `service-setup`이 바뀌면 패키지 시작/수동 재적용 명령으로 다시 검사한다. 계속 감시하는 데몬은 두지 않는다.
6. 제거 시 현재 Jellyfin 인자가 **이 SPK의 정확한 경로를 가리키는 경우에만** 원래 인자로 되돌린다. 오래된 백업으로 사용자의 후속 변경을 덮지 않는다. 드라이버 SPK 제거와 FFmpeg SPK 제거는 별도 작업이며, 드라이버 제거 시 FFmpeg SPK를 자동 삭제하지 않는다. 다만 더 이상 사용 불가능한 의존 상태를 표시한다.

## 패키지 간 설정 소유권 이전

- 새 FFmpeg SPK가 Jellyfin 경로 변경·백업·복구 및 선택적인 자동 설정을 **단독 소유**한다. `spk/bin/nvidia-backend.sh`의 과거 `/usr/local/nvidia/bin/ffmpeg` 검사와 제거 시 `.pre-nvidia.bak` 무조건 복원은 새 흐름에서 비활성화/제거해야 한다. 기존 사용자의 설정은 마이그레이션 검사를 거쳐 원본 복구 정보가 유효할 때만 인수한다.
- 설치 스크립트는 DSM 7에서 package 계정으로 실행될 수 있으므로 Jellyfin 파일을 수정해야 한다면 기존 드라이버·런타임 SPK와 같은 **범위가 좁은 setuid helper** 패턴을 검토한다. helper는 고정된 작업·경로·인자만 허용하고 임의 명령 실행 통로가 되지 않아야 한다.
- `/usr/local/nvidia/bin/ffmpeg`를 새 SPK의 설치 위치로 재사용하지 않는다. 기존 로더 주입 파일이 남아 있다면 충돌을 탐지하고 다른 패키지의 파일을 덮지 않는다.

## 빌드·배포 검증

1. `make-ffmpeg-layer.sh` 또는 새 빌더에서 원본 Jellyfin FFmpeg 아카이브의 SHA-256을 고정하고 TLS 인증을 검사한다. `ffmpeg`와 `ffprobe`의 실행 가능 여부, `ffmpeg -encoders`의 NVENC 항목, 동적 라이브러리 의존성, 해당 GPL 빌드의 출처·라이선스/소스 제공 고지를 검증한다.
2. `syno-nvidia-ffmpeg` SPK의 `INFO`, `package.tgz`, `conf/privilege`, lifecycle, helper 권한을 검사한다. 실제 릴리즈 자산의 크기·SHA-256을 드라이버 선택 매니페스트에 고정한다.
3. K4 550, K5 580을 먼저 설치·재부팅·Jellyfin 트랜스코딩·ffprobe·제거·업그레이드 시험한다. K5 595는 새 자산 또는 580 바이너리의 **실기 검증이 완료된 뒤에만** 제공한다. Plex와 Docker Jellyfin은 이 패키지 설치 여부와 관계없이 기존 동작을 유지해야 한다.
4. Jellyfin 미설치/설치 후 추가/패키지 업데이트/인자 형식 변경/권한 제한/재시작 실패, FFmpeg 다운로드 중단·해시 오류·공간 부족, 드라이버 버전 불일치 및 레거시 `/usr/local/nvidia/bin/ffmpeg` 잔존을 각각 시험한다. 실패가 NAS 부팅이나 드라이버·Monitor의 정상 상태를 해치지 않아야 한다.

이 문서는 설계만 확정한다. **현재 릴리즈에 FFmpeg SPK가 있다는 뜻이 아니며**, 구현·실기 검증 전에는 로더의 기존 FFmpeg 계층 옵션을 새 SPK 설치 완료로 표시하면 안 된다.
