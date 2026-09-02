# Synology NVIDIA GPU Monitor 0.6.1

![NVIDIA GPU Monitor](GPU-MONITOR.png)

## 한국어

DSM에서 NVIDIA GPU 상태를 한눈에 확인할 수 있는 독립형 모니터입니다.

### 주요 기능

- GPU 사용률 및 최근 변화 그래프
- VRAM 사용률과 `Used MiB / Total MiB`
- NVENC·NVDEC 사용률
- GPU 온도 및 팬 속도
- GPU Clock·Memory Clock
- DSM 메인 메뉴에서 플로팅 창으로 실행
- NVIDIA NVML 기반 실시간 조회

### 독립 모니터로 전환한 이유

DSM Resource Monitor의 GPU 데이터 API는 외부 패키지가 공식적으로 확장할 수 없는 내부 API입니다. 따라서 DSM 내부 파일이나 사설 라이브러리를 변경하지 않고, 업데이트에도 안전한 별도 GPU 모니터로 제공하도록 전환했습니다.

## English

An independent GPU monitor for viewing NVIDIA GPU status at a glance on DSM.

### Highlights

- GPU utilization with a scrolling history graph
- VRAM utilization and `Used MiB / Total MiB`
- NVENC and NVDEC utilization
- GPU temperature and fan speed
- GPU Clock and Memory Clock
- Floating window launched from the DSM main menu
- Real-time data collected through NVIDIA NVML

### Why an independent monitor?

DSM's GPU data API used by Resource Monitor is an internal interface without a supported extension path for third-party packages. The independent monitor avoids modifying DSM-owned files or private libraries and remains safer across DSM updates.
