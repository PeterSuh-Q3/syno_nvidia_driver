/* Temporary KMS pilot shim: map Linux DMA-BUF backport APIs to provider exports. */
#define LINUX_DMABUF_BACKPORT(__sym) dmabufbkpt_##__sym
#define BPM_ADD_BACKPORT_MACRO_TO_DMA_BUF_SYMBOLS 1
