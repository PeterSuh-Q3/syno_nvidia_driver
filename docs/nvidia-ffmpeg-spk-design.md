# NVIDIA FFmpeg 독립 SPK 설계

상태: FFmpeg 7/8 별도 패키지 ID 및 Jellyfin 경로 마이그레이션 구현. 신규 FFmpeg 8 패키지의 실기 설치 검증은 대기 중.

소유 저장소: `syno_nvidia_driver` — FFmpeg 패키지 소스·빌드·릴리즈. 로더의 다운로드·검증·설치 연결은 `tcrp-addons/nvidiadriver/docs/spk-delivery-design.md`를 따른다.

## 목표와 경계

NVIDIA 드라이버에 맞는 Jellyfin FFmpeg를 DSM용 독립 SPK로 제공한다. FFmpeg 7과 FFmpeg 8은 같은 패키지 ID나 설치 경로를 공유하지 않는다. 패키지는 SynoCommunity FFmpeg 패키지의 파일을 덮지 않고, 자체 `target` 아래에 바이너리를 설치한다. Jellyfin의 `service-setup`이 알려진 정확한 기본 경로를 지정한 경우에만 NVIDIA FFmpeg로 전환하며, 백업·복구는 각 패키지가 자신의 변경만 소유한다.

Plex는 자체 트랜스코더를 사용하므로 이 패키지는 Plex용 필수 구성요소가 아니다. Docker Jellyfin 컨테이너의 파일·설정도 자동 변경하지 않는다. 이 패키지가 활성화하는 것은 FFmpeg 바이너리 경로이며, Jellyfin의 하드웨어 가속 설정(예: `EnableHwAcceleration`)과 코덱별 선택은 별도 설정·검증 대상이다.

## 패키지 분리 정책

| 패키지 | ID | 현재 드라이버 대상 | Jellyfin 기본 경로 | NVIDIA 패키지 경로 |
|---|---|---|---|---|
| NVIDIA FFmpeg 7 | `syno-nvidia-ffmpeg` | 550.163.01, 580.173.02 | `/var/packages/ffmpeg7/target/bin/ffmpeg` | `/var/packages/syno-nvidia-ffmpeg/target/bin/ffmpeg` |
| NVIDIA FFmpeg 8 | `syno-nvidia-ffmpeg8-580` | 580.173.02 | `/var/packages/ffmpeg8/target/bin/ffmpeg` | `/var/packages/syno-nvidia-ffmpeg8-580/target/bin/ffmpeg` |
| NVIDIA FFmpeg 8 | `syno-nvidia-ffmpeg8` | 595.99.02 | `/var/packages/ffmpeg8/target/bin/ffmpeg` | `/var/packages/syno-nvidia-ffmpeg8/target/bin/ffmpeg` |

- FFmpeg 7의 기존 패키지 ID를 유지해 550/580 사용자의 설치·업그레이드 경로를 보존한다. FFmpeg 8은 별도 ID, 서비스 계정, 그룹 및 파일 경로를 갖는다.
- FFmpeg 8의 원본은 Jellyfin FFmpeg `8.1.3-1` portable x86_64이며 Jellyfin 12 이상에만 자동 연동한다. 580과 595는 드라이버 버전 검사를 유지하기 위해 별도 패키지 ID로 제공한다. Video Codec SDK 13의 Linux 요구 드라이버는 R570 이상이므로 R580은 API 최소 요구를 충족하지만, 실기에서 NVENC/NVDEC 인코딩·디코딩을 별도로 검증해야 한다.
- 같은 패키지 ID 안에서 FFmpeg 7/8 바이너리를 교체하지 않는다. 595용 기존 `syno-nvidia-ffmpeg` 설치본에서 새 ID로 옮길 때 새 패키지 설치와 경로 전환을 먼저 성공시킨 후 구 패키지를 제거한다. 구 패키지 제거 훅은 Jellyfin이 새 경로를 사용 중이면 이를 되돌리지 않는다.
- `ffmpeg8` 패키지의 `/var/packages/ffmpeg8/target/bin/ffmpeg`를 덮어쓰거나 소유권을 가져오지 않는다. FFmpeg 코덱 지원은 FFmpeg 빌드에 포함되어야 하며 런타임 라이브러리 파일을 추가한다고 기존 바이너리에 NVDEC/NVENC가 생기지 않는다.

## 드라이버·FFmpeg 매칭과 설치

드라이버 패키지 ID는 flavor와 DSM/커널별로 다르므로 정적 `install_dep_packages`는 비워 둔다. `preinst`와 설치 후 백엔드는 flavor별 580/595 드라이버 ID와 기존 550/K4 ID를 검사하고, 패키지에 기록된 정확한 NVIDIA 드라이버 버전과 일치해야 설치·연동한다. 설치 후 활성 커널 드라이버 버전도 다시 검사한다. 드라이버 교체 후 아직 재부팅 전이라 실행 버전이 다르면 FFmpeg 패키지는 경로를 변경하지 않고 대기한다.

Jellyfin 연동은 `/var/packages/jellyfin/scripts/service-setup`의 `--ffmpeg` 인자가 패키지별로 인식된 기본 FFmpeg 경로와 정확히 일치할 때만 적용한다. FFmpeg 8은 기본 `ffmpeg8` 경로 또는 이 패키지의 구 ID 경로를 인식해 마이그레이션한다. 알 수 없는 형식이면 파일을 건드리지 않고 로그에 수동 설정 필요를 남긴다. 변경 전 원본을 보존하고, 변경 후 Jellyfin 재시작이 실패하면 인자만 되돌린다. 제거 시 현재 인자가 해당 패키지의 정확한 FFmpeg 경로일 때만 저장된 이전 경로로 복구한다.

`encoding.xml`의 하드웨어 가속·코덱 설정은 별도 설정이다. 패키지가 실행 파일 경로를 전환했다고 해서 `EnableHwAcceleration`이 활성화되었다고 간주하지 않는다. 자동 변경은 사용자 동의와 별도 정책 없이는 수행하지 않으며, 설치 후 Jellyfin 대시보드에서 하드웨어 가속을 켜고 NVENC/NVDEC 동작을 검증해야 한다.

## 권한과 파일 소유권

- 두 패키지는 서로 다른 DSM 서비스 계정과 그룹을 사용하고, 각각 자기 `target` 파일만 소유한다.
- Jellyfin `service-setup` 변경은 고정된 작업만 허용하는 setuid helper를 통한다. helper는 임의 명령 실행 수단이 되지 않으며, 서비스 파일의 기존 inode·소유자·권한을 보존한다.
- 패키지 업데이트로 Jellyfin의 기본 FFmpeg 인자나 파일이 달라지면 자동 변경하지 않고 로그를 남긴다. 다른 패키지의 `target`, 심볼릭 링크 또는 설정을 덮지 않는다.

## 빌드와 검증

`scripts/build-ffmpeg-spk.sh`는 출처별 고정 SHA-256을 확인하고 세대별 SPK를 만든다. 550/580 패키지는 ID `syno-nvidia-ffmpeg`의 FFmpeg 7, 580용 FFmpeg 8은 ID `syno-nvidia-ffmpeg8-580`, 595용 FFmpeg 8은 ID `syno-nvidia-ffmpeg8`로 패킹한다. 패킹 후 SPK의 `INFO`, helper 경로, lifecycle 스크립트, 사용자/그룹, FFmpeg/FFprobe, 출처·라이선스 메타데이터를 검사한다.

검증은 각 패키지에 대해 순서대로 한다.

1. NVIDIA 드라이버 ID·버전 불일치 시 설치가 거부되는지, 일치하지만 실행 드라이버 버전이 이전일 때 Jellyfin 경로 변경이 보류되는지 확인한다.
2. Jellyfin 기본 인자가 있는 경우에만 경로가 바뀌고, 미지원 인자·Jellyfin 미설치에서는 파일을 변경하지 않는지 확인한다.
3. FFmpeg가 `-hwaccels`, `-decoders`, `-encoders`에서 예상 NVIDIA 기능을 노출하는지 확인하고, 실기에서 NVDEC 디코딩과 NVENC 인코딩을 각각 시험한다.
4. Jellyfin 하드웨어 가속 설정이 실제로 켜져 있는지와 재생 로그의 입력/출력 코덱 및 GPU 사용률을 확인한다. FFmpeg 경로 전환 성공만으로 H/W 트랜스코딩 성공으로 판정하지 않는다.
5. FFmpeg 8은 Jellyfin 12 이상에서만 자동 연동되는지, 구 ID의 595 패키지에서 새 ID로 이동할 때 설치·경로 전환·구 패키지 제거가 안전한지 확인한다.

현재 595 FFmpeg 8 원본은 Jellyfin FFmpeg `8.1.3-1`이며, 다운로드 아카이브 SHA-256은 `b86dc023c64a5a9a410e6e3a938a970460214fae78f31c1553c9f88f1c289b6a`로 고정한다. 사용자용 패키지 설명과 릴리즈 노트는 FFmpeg 세대, NVIDIA 드라이버 버전, Jellyfin 서버 호환 범위, 하드웨어 가속 설정이 별도 필요하다는 점을 간결하게 안내한다.
