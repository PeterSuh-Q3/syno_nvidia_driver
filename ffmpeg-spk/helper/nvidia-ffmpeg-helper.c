#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef PACKAGE_ID
#define PACKAGE_ID "syno-nvidia-ffmpeg"
#endif
#define BACKEND "/var/packages/" PACKAGE_ID "/target/bin/nvidia-ffmpeg-backend.sh"

int main(int argc, char *argv[])
{
    if (argc != 2 || (strcmp(argv[1], "postinst") != 0 &&
                      strcmp(argv[1], "start") != 0 &&
                      strcmp(argv[1], "uninstall") != 0 &&
                      strcmp(argv[1], "configure") != 0)) {
        fputs("nvidia-ffmpeg-helper: invalid action\n", stderr);
        return 1;
    }
    if (setuid(0) != 0 || clearenv() != 0 ||
        setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin:/usr/syno/bin", 1) != 0 ||
        setenv("HOME", "/root", 1) != 0) {
        perror("nvidia-ffmpeg-helper: privilege setup");
        return 1;
    }
    execl(BACKEND, BACKEND, argv[1], (char *)NULL);
    perror("nvidia-ffmpeg-helper: exec");
    return 1;
}
