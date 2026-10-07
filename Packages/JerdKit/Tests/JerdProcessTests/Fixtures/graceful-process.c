#include <signal.h>
#include <stdio.h>
#include <unistd.h>

static volatile sig_atomic_t done = 0;
static void finish(int signal) { (void)signal; done = 1; }

int main(void) {
    signal(SIGTERM, SIG_IGN);
    signal(SIGINT, finish);
    puts("ready");
    fflush(stdout);
    while (!done) pause();
    return 0;
}
