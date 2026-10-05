#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

// Test fixture only. Writes its PID to sleeper.pid in the working folder, then sleeps.
// With "signal", it ends itself with SIGTERM. With "ignore-term", it ignores SIGTERM.
int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "signal") == 0) raise(SIGTERM);
    if (argc > 1 && strcmp(argv[1], "ignore-term") == 0) signal(SIGTERM, SIG_IGN);
    FILE *file = fopen("sleeper.pid.tmp", "w");
    if (!file) return 2;
    fprintf(file, "%d\n", getpid());
    fclose(file);
    rename("sleeper.pid.tmp", "sleeper.pid");
    puts("ready");
    fflush(stdout);
    sleep(30); // Fail-safe end if a test cannot stop the fixture.
    return 0;
}
