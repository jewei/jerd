#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

// Test fixture only. Reports what the spawner promises: open descriptors, the signal mask and
// actions, the process group, standard input, the working folder, and inherited listener ports.
int main(void) {
    printf("descriptors:");
    for (int fd = 0; fd < 256; fd++) {
        if (fcntl(fd, F_GETFD) != -1) printf(" %d", fd);
    }
    printf("\n");
    sigset_t mask;
    sigprocmask(SIG_BLOCK, NULL, &mask);
    int blocked = 0, ignored = 0;
    for (int number = 1; number < NSIG; number++) {
        struct sigaction action;
        if (sigismember(&mask, number)) blocked++;
        if (sigaction(number, NULL, &action) == 0 && action.sa_handler == SIG_IGN) ignored++;
    }
    printf("blocked: %d\nignored: %d\n", blocked, ignored);
    printf("group-leader: %s\n", getpgrp() == getpid() ? "yes" : "no");
    struct stat input, null;
    int same = fstat(0, &input) == 0 && stat("/dev/null", &null) == 0 && input.st_rdev == null.st_rdev;
    printf("stdin-null: %s\n", same ? "yes" : "no");
    char folder[2048];
    printf("cwd: %s\n", getcwd(folder, sizeof folder) ? folder : "?");
    for (int fd = 3; fd <= 4; fd++) {
        struct sockaddr_in address;
        socklen_t length = sizeof address;
        if (getsockname(fd, (struct sockaddr *)&address, &length) == 0) {
            printf("listener-%d: %d\n", fd, ntohs(address.sin_port));
        }
    }
    return 0;
}
