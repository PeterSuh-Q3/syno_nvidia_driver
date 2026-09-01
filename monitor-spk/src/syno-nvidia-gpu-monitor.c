/*
 * Synology NVIDIA GPU Monitor - Phase 1 telemetry collector.
 *
 * NVML is intentionally dlopen()ed from the NVIDIA driver's private runtime
 * directory.  This avoids a global loader change and keeps the collector
 * independent from a particular NVIDIA driver build at compile time.
 */
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef int nvmlReturn_t;
typedef struct nvmlDevice_st *nvmlDevice_t;
typedef struct {
    unsigned int gpu;
    unsigned int memory;
} nvmlUtilization_t;
typedef struct {
    unsigned long long total;
    unsigned long long free;
    unsigned long long used;
} nvmlMemory_t;

#define NVML_SUCCESS 0

typedef nvmlReturn_t (*nvmlInit_v2_fn)(void);
typedef nvmlReturn_t (*nvmlShutdown_fn)(void);
typedef nvmlReturn_t (*nvmlDeviceGetCount_v2_fn)(unsigned int *);
typedef nvmlReturn_t (*nvmlDeviceGetHandleByIndex_v2_fn)(unsigned int, nvmlDevice_t *);
typedef nvmlReturn_t (*nvmlDeviceGetUtilizationRates_fn)(nvmlDevice_t, nvmlUtilization_t *);
typedef nvmlReturn_t (*nvmlDeviceGetMemoryInfo_fn)(nvmlDevice_t, nvmlMemory_t *);

struct nvml_api {
    void *handle;
    nvmlInit_v2_fn init;
    nvmlShutdown_fn shutdown;
    nvmlDeviceGetCount_v2_fn count;
    nvmlDeviceGetHandleByIndex_v2_fn device;
    nvmlDeviceGetUtilizationRates_fn utilization;
    nvmlDeviceGetMemoryInfo_fn memory;
};

static int load_nvml(struct nvml_api *api) {
    static const char *const paths[] = {
        "/usr/local/nvidia/lib/libnvidia-ml.so.1",
        "libnvidia-ml.so.1",
        NULL
    };
    unsigned int i;

    memset(api, 0, sizeof(*api));
    for (i = 0; paths[i] != NULL; ++i) {
        api->handle = dlopen(paths[i], RTLD_NOW | RTLD_LOCAL);
        if (api->handle != NULL) break;
    }
    if (api->handle == NULL) return -1;

    api->init = (nvmlInit_v2_fn)dlsym(api->handle, "nvmlInit_v2");
    api->shutdown = (nvmlShutdown_fn)dlsym(api->handle, "nvmlShutdown");
    api->count = (nvmlDeviceGetCount_v2_fn)dlsym(api->handle, "nvmlDeviceGetCount_v2");
    api->device = (nvmlDeviceGetHandleByIndex_v2_fn)dlsym(api->handle, "nvmlDeviceGetHandleByIndex_v2");
    api->utilization = (nvmlDeviceGetUtilizationRates_fn)dlsym(api->handle, "nvmlDeviceGetUtilizationRates");
    api->memory = (nvmlDeviceGetMemoryInfo_fn)dlsym(api->handle, "nvmlDeviceGetMemoryInfo");
    if (api->init == NULL || api->shutdown == NULL || api->count == NULL ||
        api->device == NULL || api->utilization == NULL || api->memory == NULL) {
        dlclose(api->handle);
        memset(api, 0, sizeof(*api));
        return -1;
    }
    return 0;
}

int main(int argc, char **argv) {
    struct nvml_api api;
    nvmlDevice_t device;
    nvmlUtilization_t utilization;
    nvmlMemory_t memory;
    unsigned int count = 0;
    unsigned long long total_kib, used_kib, free_kib;
    unsigned int memory_percent;
    int check_only = 0;
    int rc = 1;

    if (argc == 2 && strcmp(argv[1], "--check") == 0) check_only = 1;
    else if (argc != 1 && !(argc == 2 && strcmp(argv[1], "--json") == 0)) {
        fprintf(stderr, "Usage: %s [--check|--json]\n", argv[0]);
        return 2;
    }

    if (load_nvml(&api) != 0) {
        fprintf(stderr, "NVML library is unavailable. Install and start a supported syno-nvidia-driver package first.\n");
        return 1;
    }
    if (api.init() != NVML_SUCCESS || api.count(&count) != NVML_SUCCESS || count == 0 ||
        api.device(0, &device) != NVML_SUCCESS) {
        fprintf(stderr, "NVML cannot access an NVIDIA GPU.\n");
        goto out;
    }
    if (check_only) {
        rc = 0;
        goto out;
    }
    if (api.utilization(device, &utilization) != NVML_SUCCESS ||
        api.memory(device, &memory) != NVML_SUCCESS) {
        fprintf(stderr, "NVML telemetry query failed.\n");
        goto out;
    }

    total_kib = memory.total / 1024ULL;
    used_kib = memory.used / 1024ULL;
    free_kib = memory.free / 1024ULL;
    memory_percent = total_kib == 0 ? 0U : (unsigned int)((used_kib * 100ULL) / total_kib);
    printf("{\"device\":\"Gpu\",\"gpu_utilization\":%u,\"gpu_memory_total\":%llu,"
           "\"gpu_memory_used\":%llu,\"gpu_memory_free\":%llu,\"gpu_memory_utilization\":%u}\n",
           utilization.gpu, total_kib, used_kib, free_kib, memory_percent);
    rc = 0;
out:
    api.shutdown();
    dlclose(api.handle);
    return rc;
}
