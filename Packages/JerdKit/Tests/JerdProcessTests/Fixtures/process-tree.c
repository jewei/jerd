#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>

static volatile sig_atomic_t stopping = 0;
static void stop(int signal) { stopping = 1; }

// Test fixture only. The child stays in the new process group after its parent exits.
int main(int argc, char **argv) {
    int ready[2];
    if (pipe(ready) != 0) return 1;
    pid_t child = fork();
    if (child < 0) return 1;
    if (child == 0) {
        close(ready[0]);
        if (argc > 1) signal(SIGTERM, stop);
        // Tell the leader that the cleanup handler is installed.
        if (write(ready[1], "r", 1) != 1) return 3;
        close(ready[1]);
        if (argc > 1) {
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
    // Exit only after the child has installed its cleanup handler.
    close(ready[1]);
    char byte;
    if (read(ready[0], &byte, 1) != 1) return 4;
    close(ready[0]);
    printf("%d\n", child);
    fflush(stdout);
    return 0;
}
