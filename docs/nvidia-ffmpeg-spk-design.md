# NVIDIA FFmpeg 독립 SPK 설계

상태: 5개 조합을 고유 패키지 ID·경로로 정비하며, 패키지 표시명은 모두 `Synology NVIDIA FFmpeg <세대> (<드라이버>)` 형식으로 통일한다. 580 FFmpeg 8의 재시작 알림 파일럿 SPK(-2)를 빌드했으며, DSM 실기에서 알림과 기동 판정 검증은 남아 있다. 595용 FFmpeg 7은 Jellyfin FFmpeg 7.1.4-3 자산을 후보로 삼아 드라이버 호환성을 검증한다.

소유 저장소: `syno_nvidia_driver` — FFmpeg 패키지 소스·빌드·릴리즈. 로더의 다운로드·검증·설치 연결은 `tcrp-addons/nvidiadriver/docs/spk-delivery-design.md`를 따른다.

## 목표와 경계

NVIDIA 드라이버에 맞는 Jellyfin FFmpeg를 DSM용 독립 SPK로 제공한다. FFmpeg 7과 FFmpeg 8은 같은 패키지 ID나 설치 경로를 공유하지 않는다. 패키지는 SynoCommunity FFmpeg 패키지의 파일을 덮지 않고, 자체 `target` 아래에 바이너리를 설치한다. Jellyfin의 `service-setup`이 알려진 정확한 기본 경로를 지정한 경우에만 NVIDIA FFmpeg로 전환하며, 백업·복구는 각 패키지가 자신의 변경만 소유한다.

Plex는 자체 트랜스코더를 사용하므로 이 패키지는 Plex용 필수 구성요소가 아니다. Docker Jellyfin 컨테이너의 파일·설정도 자동 변경하지 않는다. 이 패키지가 활성화하는 것은 FFmpeg 바이너리 경로이며, Jellyfin의 하드웨어 가속 설정(예: `EnableHwAcceleration`)과 코덱별 선택은 별도 설정·검증 대상이다.

## 패키지 분리 정책

| 패키지 타이틀 | ID | 드라이버 | Jellyfin 기본 경로 | NVIDIA 패키지 경로 |
|---|---|---|---|---|
| `Synology NVIDIA FFmpeg 7 (550)` | `syno-nvidia-ffmpeg7-550` | 550.163.01 | `/var/packages/ffmpeg7/target/bin/ffmpeg` | `/var/packages/syno-nvidia-ffmpeg7-550/target/bin/ffmpeg` |
| `Synology NVIDIA FFmpeg 7 (580)` | `syno-nvidia-ffmpeg7-580` | 580.173.02 | `/var/packages/ffmpeg7/target/bin/ffmpeg` | `/var/packages/syno-nvidia-ffmpeg7-580/target/bin/ffmpeg` |
| `Synology NVIDIA FFmpeg 8 (580)` | `syno-nvidia-ffmpeg8-580` | 580.173.02 | `/var/packages/ffmpeg8/target/bin/ffmpeg` | `/var/packages/syno-nvidia-ffmpeg8-580/target/bin/ffmpeg` |
| `Synology NVIDIA FFmpeg 7 (595)` | `syno-nvidia-ffmpeg7-595` | 595.99.02 | `/var/packages/ffmpeg7/target/bin/ffmpeg` | `/var/packages/syno-nvidia-ffmpeg7-595/target/bin/ffmpeg` |
| `Synology NVIDIA FFmpeg 8 (595)` | `syno-nvidia-ffmpeg8-595` | 595.99.02 | `/var/packages/ffmpeg8/target/bin/ffmpeg` | `/var/packages/syno-nvidia-ffmpeg8-595/target/bin/ffmpeg` |

- NVIDIA 버전과 FFmpeg 세대의 모든 지원 조합은 별도 ID·계정·그룹·설치 경로를 가진다. `syno-nvidia-ffmpeg`는 550/580 FFmpeg 7에서 공유되어 충돌하므로 폐기하고, 550/580용 개별 ID로 대체한다.
- 현재 고유 ID인 `syno-nvidia-ffmpeg8-580`은 유지한다. 595 FFmpeg 8은 기존 `syno-nvidia-ffmpeg8`에서 `syno-nvidia-ffmpeg8-595`로 이동해 같은 `syno-nvidia-ffmpeg#-###` 규칙을 적용한다.
- 550은 FFmpeg 7만 제공한다. FFmpeg 8은 Jellyfin FFmpeg `8.1.3-1` portable x86_64를 사용하며 Jellyfin 12 이상에만 자동 연동한다. 현재 설계 자료상 이 빌드 계열은 드라이버 R570 이상을 요구하므로 550용 FFmpeg 8은 제공하지 않는다.
- 595용 FFmpeg 7은 Jellyfin FFmpeg `7.1.4-3`을 후보로 하며, 580에서 사용 중인 FFmpeg 7 binary/API 세대가 595 드라이버와 호환되는지 확인한 뒤 자산을 확정한다. 595용 FFmpeg 7은 Jellyfin 7 이상을 대상으로 한다.
- 595 FFmpeg 7 후보 자산은 `out/ffmpeg7-595-compatibility-pilot/nv-ffmpeg7-595.99.02.tgz`에 생성했다. 출처는 Jellyfin FFmpeg `7.1.4-3` portable linux64-gpl이며, 압축 아카이브 SHA-256은 `5f5b5e3eeec99e1c3aafef15cdecbc5f05028465e76498d0fa728a7dc6caa418`이다. 후보 FFmpeg/FFprobe 바이너리 해시는 기존 580 FFmpeg 7 자산과 각각 일치한다 (`e1c797039bb43addea6a9fe5496a11880ad2393344f6261e828b7f2f87dc0b10`, `be9cec51cf92e65ef600b702693b6248eaf9a718c9b71b75a689fdf6672f81c1`). 이는 동일한 FFmpeg 실행물을 재사용했다는 증거이지, 아직 595 드라이버 실기에서 NVENC/NVDEC가 작동한다는 검증은 아니다. NVIDIA는 NVENC API의 바이너리 하위호환을 명시하므로 구 API로 빌드한 앱의 새 드라이버 호환성은 설계상 기대할 수 있지만, 실제 595 GPU에서 인코딩·디코딩 검증 후에만 최종 배포 자산으로 승격한다: https://docs.nvidia.com/video-technologies/video-codec-sdk/13.0/nvenc-video-encoder-api-prog-guide/index.html
- 같은 패키지 ID 안에서 FFmpeg 7/8 바이너리를 교체하지 않는다. 구 ID 설치본에서 새 ID로 옮길 때 새 패키지 설치와 경로 전환, Jellyfin 재시작이 성공한 후 구 패키지를 제거한다. 구 패키지 제거 훅은 Jellyfin이 새 경로를 사용 중이면 이를 되돌리지 않는다.
- `ffmpeg8` 패키지의 `/var/packages/ffmpeg8/target/bin/ffmpeg`를 덮어쓰거나 소유권을 가져오지 않는다. FFmpeg 코덱 지원은 FFmpeg 빌드에 포함되어야 하며 런타임 라이브러리 파일을 추가한다고 기존 바이너리에 NVDEC/NVENC가 생기지 않는다.

## 드라이버·FFmpeg 매칭과 설치

드라이버 패키지 ID는 flavor와 DSM/커널별로 다르므로 정적 `install_dep_packages`는 비워 둔다. `preinst`와 설치 후 백엔드는 flavor별 580/595 드라이버 ID와 기존 550/K4 ID를 검사하고, 패키지에 기록된 정확한 NVIDIA 드라이버 버전과 일치해야 설치·연동한다. 설치 후 활성 커널 드라이버 버전도 다시 검사한다. 드라이버 교체 후 아직 재부팅 전이라 실행 버전이 다르면 FFmpeg 패키지는 경로를 변경하지 않고 대기한다.

Jellyfin 연동은 `/var/packages/jellyfin/scripts/service-setup`의 `--ffmpeg` 인자가 해당 FFmpeg 세대의 기본 경로 또는 명시적으로 지원하는 이전 NVIDIA 패키지 경로와 일치할 때만 적용한다. 알 수 없는 형식이면 파일을 건드리지 않고 수동 설정 안내를 남긴다. 설정 변경 전 DSM 데스크톱 알림으로 Jellyfin 재시작 예정임을 알리고, 재시작 요청 후 최대 120초 동안 패키지 실행 상태와 실제 Jellyfin 프로세스의 새 `--ffmpeg` 경로를 확인한다. 확인 성공·실패·시간 초과는 다시 데스크톱 알림으로 알린다. 확인에 실패하면 서비스 인자를 이전 경로로 되돌리고 Jellyfin을 다시 시작하되, FFmpeg SPK 자체는 설치된 상태로 유지한다. Jellyfin이 원래 중지되어 있으면 경로만 변경하고 자동으로 시작하지 않았음을 알린다. 제거 시 현재 인자가 그 패키지의 정확한 경로일 때만 저장된 이전 경로로 복구한다.

`encoding.xml`의 하드웨어 가속·코덱 설정은 별도 설정이다. 패키지가 실행 파일 경로를 전환했다고 해서 `EnableHwAcceleration`이 활성화되었다고 간주하지 않는다. 자동 변경은 사용자 동의와 별도 정책 없이는 수행하지 않으며, 설치 후 Jellyfin 대시보드에서 하드웨어 가속을 켜고 NVENC/NVDEC 동작을 검증해야 한다.

## 권한과 파일 소유권

- 두 패키지는 서로 다른 DSM 서비스 계정과 그룹을 사용하고, 각각 자기 `target` 파일만 소유한다.
- Jellyfin `service-setup` 변경은 고정된 작업만 허용하는 setuid helper를 통한다. helper는 임의 명령 실행 수단이 되지 않으며, 서비스 파일의 기존 inode·소유자·권한을 보존한다.
- 패키지 업데이트로 Jellyfin의 기본 FFmpeg 인자나 파일이 달라지면 자동 변경하지 않고 로그를 남긴다. 다른 패키지의 `target`, 심볼릭 링크 또는 설정을 덮지 않는다.

## 빌드와 검증

`scripts/build-ffmpeg-spk.sh`는 5개 조합을 각각 패킹한다. 550/7, 580/7·8, 595/7·8의 ID는 위 표와 동일하며 패키지별 실행 바이너리는 반드시 `/var/packages/<package-id>/target/bin/ffmpeg`에 놓는다. 캐시 카탈로그는 새 5개 ID를 등록하고, 충돌하던 `syno-nvidia-ffmpeg`와 595 FFmpeg 8의 구 ID를 제거한다. 580 FFmpeg 8 ID는 유지한다. 패킹 후 SPK의 `INFO`, `package-id`, 기본 Jellyfin 경로, driver version, helper 경로, 계정·그룹, FFmpeg/FFprobe, 출처·라이선스 메타데이터를 검사한다.

검증은 각 패키지에 대해 순서대로 한다.

1. NVIDIA 드라이버 ID·버전 불일치 시 설치가 거부되는지, 일치하지만 실행 드라이버 버전이 이전일 때 Jellyfin 경로 변경이 보류되는지 확인한다.
2. Jellyfin 기본 인자가 있는 경우에만 경로가 바뀌고, 미지원 인자·Jellyfin 미설치에서는 파일을 변경하지 않는지 확인한다.
3. FFmpeg가 `-hwaccels`, `-decoders`, `-encoders`에서 예상 NVIDIA 기능을 노출하는지 확인하고, 실기에서 NVDEC 디코딩과 NVENC 인코딩을 각각 시험한다.
4. Jellyfin 하드웨어 가속 설정이 실제로 켜져 있는지와 재생 로그의 입력/출력 코덱 및 GPU 사용률을 확인한다. FFmpeg 경로 전환 성공만으로 H/W 트랜스코딩 성공으로 판정하지 않는다.
5. FFmpeg 8은 Jellyfin 12 이상에서만 자동 연동되는지 확인한다. 각 패키지 설치 후 Jellyfin 설정 파일과 실행 프로세스가 같은 고유 경로를 가리키고, Jellyfin 재시작까지 성공했는지 확인한다.
6. 595 FFmpeg 7은 595 드라이버 실기에서 NVDEC와 NVENC를 각각 검증한 뒤 배포 자산으로 확정한다.

현재 595 FFmpeg 8 원본은 Jellyfin FFmpeg `8.1.3-1`이며, 다운로드 아카이브 SHA-256은 `b86dc023c64a5a9a410e6e3a938a970460214fae78f31c1553c9f88f1c289b6a`로 고정한다. 사용자용 패키지 설명과 릴리즈 노트는 FFmpeg 세대, NVIDIA 드라이버 버전, Jellyfin 서버 호환 범위, 하드웨어 가속 설정이 별도 필요하다는 점을 간결하게 안내한다.
