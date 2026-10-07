#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>

// No network or database work. Markers control a master and its stubborn child.
int main(int argc, char **argv) {
    pid_t child = fork();
    if (child < 0) return 1;
    if (child == 0) {
        signal(SIGTERM, SIG_IGN);
        FILE *pid = fopen("child.pid", "w");
        if (!pid) return 2;
        fprintf(pid, "%d\n", getpid()); fclose(pid);
        // The deadline also limits the test if its controller exits unexpectedly.
        for (int i = 0; i < 1500 && access("finish-child", F_OK) != 0; i++) usleep(20000);
        return 0;
    }
    while (access("child.pid", F_OK) != 0) usleep(1000);
    puts("ready"); fflush(stdout);
    while (access("exit-master", F_OK) != 0) usleep(1000);
    return 0;
}
