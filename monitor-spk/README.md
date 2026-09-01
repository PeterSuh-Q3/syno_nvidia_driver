# Synology NVIDIA GPU Monitor — Phase 1

This experimental, install-only SPK provides one read-only command:

```sh
/var/packages/syno-nvidia-gpu-monitor/target/bin/syno-nvidia-gpu-monitor --json
```

It emits the DSM GPU metric schema using NVML and KiB memory units.  It has no
daemon, makes no global loader changes, and does **not** modify DSM Resource
Monitor.  A supported `syno-nvidia-driver` runtime must already be active.

The DSM Resource Monitor bridge remains a separate Phase 2 research task.
