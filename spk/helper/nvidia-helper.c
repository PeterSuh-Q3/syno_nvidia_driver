/*
 * nvidia-helper.c
 *
 * Narrow setuid-root launcher for syno-nvidia-driver, same pattern as
 * MshellManager's mshell-helper.c and SynoSmartInfo's smartinfo-helper.c
 * (see /Users/yousuk/mshell-manager/docs/synology-spk-build-notes.md):
 * on DSM 7.4.1, third-party postinst/preuninst/start-stop-status scripts
 * run as the conf/privilege-declared "package" service account, not root
 * (confirmed directly on real hardware - "installer scripts always run
 * as root" is not true here) - and conf/privilege cannot declare
 * "run-as": "root" at all (DSM rejects the whole install with error 319).
 * So every lifecycle script in this package execs THIS binary instead of
 * doing privileged work itself; DSM applies root-owned setuid to this
 * exact binary at install time via conf/privilege's "tool" section.
 *
 * TARGET_SCRIPT is baked in at compile time (see scripts/build-spk.sh's
 * -DTARGET_SCRIPT) because it differs per package variant
 * (syno-nvidia-driver-kver5 / -kver4-dsm72 / -kver4-dsm70 each install
 * to a different /var/packages/<name>/target).
 */

#define _GNU_SOURCE
#include <unistd.h>
extern int clearenv(void);
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#ifndef TARGET_SCRIPT
#define TARGET_SCRIPT "/var/packages/syno-nvidia-driver/target/bin/nvidia-backend.sh"
#endif

int main(int argc, char *argv[])
{
    /* Every privileged operation this package ever needs, named by
     * lifecycle stage rather than by raw command, so the helper can't be
     * repurposed into an arbitrary-root-command launcher. */
    const char *allowed_actions[] = { "postinst", "start", "uninstall", NULL };

    if (argc != 2) {
        fprintf(stderr, "nvidia-helper: expected exactly 1 argument, got %d\n", argc - 1);
        return 1;
    }

    const char *action = argv[1];
    int ok = 0;
    for (int i = 0; allowed_actions[i] != NULL; i++) {
        if (strcmp(action, allowed_actions[i]) == 0) { ok = 1; break; }
    }
    if (!ok) {
        fprintf(stderr, "nvidia-helper: rejected action '%s'\n", action);
        return 1;
    }

    /* setuid binary gives us euid=0; promote ruid too so the exec'd
     * backend script is genuinely root, not just effectively root. */
    if (setuid(0) != 0) {
        perror("nvidia-helper: setuid(0) failed");
        return 1;
    }

    /* Sanitize environment: fixed PATH, no inherited surprises from
     * whatever the package service account's environment looked like. */
    if (clearenv() != 0) {
        fprintf(stderr, "nvidia-helper: clearenv failed\n");
        return 1;
    }
    setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin:/usr/syno/bin:/usr/syno/sbin", 1);
    setenv("HOME", "/root", 1);

    execl(TARGET_SCRIPT, TARGET_SCRIPT, action, (char *)NULL);

    perror("nvidia-helper: execl failed");
    return 1;
}
