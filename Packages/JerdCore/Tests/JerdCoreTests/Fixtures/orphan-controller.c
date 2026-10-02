#include <stdio.h>
#include <unistd.h>
#include <signal.h>

// A separate controller creates a service group, then waits to be terminated.
int main(void) {
    pid_t child = fork();
    if (child < 0) return 1;
    if (child == 0) {
        if (setsid() < 0) return 2;
        signal(SIGTERM, SIG_DFL);
        sleep(20); // Fail-safe cleanup if the test cannot request recovery.
        return 0;
    }
    usleep(50000);
    printf("%d\n", child); fflush(stdout);
    for (;;) pause();
}
