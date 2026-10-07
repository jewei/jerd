#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>

// A separate controller creates a service group, then waits to be terminated.
// With "stubborn-child", the child in the new session ignores SIGTERM.
int main(int argc, char **argv) {
    int stubborn = argc > 1 && strcmp(argv[1], "stubborn-child") == 0;
    pid_t child = fork();
    if (child < 0) return 1;
    if (child == 0) {
        if (setsid() < 0) return 2;
        signal(SIGTERM, stubborn ? SIG_IGN : SIG_DFL);
        sleep(20); // Fail-safe cleanup if the test cannot request recovery.
        return 0;
    }
    usleep(50000);
    printf("%d\n", child); fflush(stdout);
    for (;;) pause();
}
