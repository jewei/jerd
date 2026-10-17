#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>

// A separate controller creates a service group, then waits to be terminated.
// With "stubborn-child", the child in the new session ignores SIGTERM.
int main(int argc, char **argv) {
    int stubborn = argc > 1 && strcmp(argv[1], "stubborn-child") == 0;
    int ready[2];
    if (pipe(ready) != 0) return 1;
    pid_t child = fork();
    if (child < 0) return 1;
    if (child == 0) {
        close(ready[0]);
        if (setsid() < 0) return 2;
        signal(SIGTERM, stubborn ? SIG_IGN : SIG_DFL);
        // Tell the controller that the new session and the signal action are in place.
        if (write(ready[1], "r", 1) != 1) return 3;
        close(ready[1]);
        sleep(20); // Fail-safe cleanup if the test cannot request recovery.
        return 0;
    }
    close(ready[1]);
    char byte;
    if (read(ready[0], &byte, 1) != 1) return 4;
    close(ready[0]);
    printf("%d\n", child); fflush(stdout);
    for (;;) pause();
}
