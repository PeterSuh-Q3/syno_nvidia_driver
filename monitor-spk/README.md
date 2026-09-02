# Synology NVIDIA GPU Monitor — Phase 1

This SPK provides one read-only command and an optional UI
experiment:

```sh
/var/packages/syno-nvidia-gpu-monitor/target/bin/syno-nvidia-gpu-monitor --json
```

Version 0.2 additionally exposes DSM Resource Monitor's existing GPU panels
and removes only the misleading “no GPU installed” mask. It does not provide
GPU values to DSM's private Utilization API yet; uninstall restores every
modified DSM file and setting.

It emits the DSM GPU metric schema using NVML and KiB memory units.  It has no
daemon and makes no global loader changes.  The UI experiment makes a small,
backed-up change to DSM Resource Monitor's display JavaScript and restores it
on uninstall.  A supported `syno-nvidia-driver` runtime must already be active.

The DSM Resource Monitor bridge remains a separate Phase 2 research task.
