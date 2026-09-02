# Synology NVIDIA GPU Monitor 0.6.1

![NVIDIA GPU Monitor](https://raw.githubusercontent.com/PeterSuh-Q3/syno_nvidia_driver/main/docs/GPU-MONITOR.png)

## English

An independent floating GPU monitor for Synology DSM.

### Highlights

- GPU utilization with scrolling history graph
- VRAM utilization and `Used MiB / Total MiB`
- NVENC and NVDEC utilization
- GPU temperature and fan speed
- GPU Clock and Memory Clock
- Launches as a DSM floating window from the main menu
- Real-time data collected through NVIDIA NVML

### Why an independent monitor?

DSM Resource Monitor uses an internal GPU data API that third-party packages cannot extend through a supported interface. This monitor therefore uses its own NVML-based view without modifying DSM-owned libraries or private APIs, improving safety across DSM updates.

## 한국어

Synology DSM에서 NVIDIA GPU 상태를 확인하는 독립형 플로팅 모니터입니다.

### 주요 기능

- GPU 사용률 및 흐름 그래프
- VRAM 사용률과 `사용량 MiB / 전체량 MiB`
- NVENC·NVDEC 사용률
- GPU 온도 및 팬 속도
- GPU Clock·Memory Clock
- DSM 메인 메뉴에서 플로팅 창으로 실행
- NVIDIA NVML 기반 실시간 조회

### 독립형 모니터를 사용하는 이유

DSM Resource Monitor의 GPU 데이터 API는 외부 패키지가 공식적으로 확장할 수 없는 내부 인터페이스입니다. 따라서 DSM 내부 라이브러리나 비공개 API를 수정하지 않고, DSM 업데이트에도 안전한 NVML 기반 전용 화면으로 제공됩니다.
