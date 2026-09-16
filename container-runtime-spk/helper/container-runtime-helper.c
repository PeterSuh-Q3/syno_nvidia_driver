/*
 * Narrow setuid-root launcher for Synology NVIDIA Container Runtime.
 * DSM executes third-party lifecycle scripts as the package account.  This
 * helper exposes only fixed lifecycle actions to the root-owned backend.
 */
#define _GNU_SOURCE
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef TARGET_SCRIPT
#define TARGET_SCRIPT "/var/packages/syno-nvidia-container-runtime/target/bin/container-runtime-backend.sh"
#endif

int main(int argc, char *argv[])
{
    const char *allowed[] = { "postinst", "start", "uninstall", NULL };
    int valid = 0;

    if (argc != 2) {
        fprintf(stderr, "container-runtime-helper: expected one action\n");
        return 1;
    }
    for (int i = 0; allowed[i] != NULL; i++) {
        if (strcmp(argv[1], allowed[i]) == 0) {
            valid = 1;
            break;
        }
    }
    if (!valid) {
        fprintf(stderr, "container-runtime-helper: rejected action\n");
        return 1;
    }
    if (setuid(0) != 0) {
        perror("container-runtime-helper: setuid");
        return 1;
    }
    if (clearenv() != 0) {
        fprintf(stderr, "container-runtime-helper: clearenv failed\n");
        return 1;
    }
    setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin:/usr/syno/bin:/usr/syno/sbin", 1);
    setenv("HOME", "/root", 1);
    execl(TARGET_SCRIPT, TARGET_SCRIPT, argv[1], (char *)NULL);
    perror("container-runtime-helper: execl");
    return 1;
}
