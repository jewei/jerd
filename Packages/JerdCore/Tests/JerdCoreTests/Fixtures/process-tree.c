#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>

static volatile sig_atomic_t stopping = 0;
static void stop(int signal) { stopping = 1; }

// Test fixture only. The child stays in the new process group after its parent exits.
int main(int argc, char **argv) {
    pid_t child = fork();
    if (child < 0) return 1;
    if (child == 0) {
        if (argc > 1) {
            signal(SIGTERM, stop);
            while (!stopping) pause();
            usleep(300000);
            int fd = open(argv[1], O_WRONLY | O_CREAT, 0600);
            if (fd < 0) return 2;
            write(fd, "clean", 5);
            close(fd);
            return 0;
        }
        for (;;) pause();
    }
    // Give the child time to install its cleanup handler before the leader exits.
    usleep(50000);
    printf("%d\n", child);
    fflush(stdout);
    return 0;
}
