#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// Test fixture only. The child stays in the new process group after its parent exits.
int main(void) {
    pid_t child = fork();
    if (child < 0) return 1;
    if (child == 0) {
        for (;;) pause();
    }
    printf("%d\n", child);
    fflush(stdout);
    return 0;
}
