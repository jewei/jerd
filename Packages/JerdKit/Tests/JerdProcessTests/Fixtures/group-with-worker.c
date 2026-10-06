#include <signal.h>
#include <stdio.h>
#include <sys/wait.h>
#include <unistd.h>

// A leader with one worker in its process group, like a database server and its backend.
// On SIGINT the leader asks the worker to end (SIGTERM) and waits for it. Both catch their
// signal, so a paused process keeps it pending until it continues. The leader prints the
// worker PID when the worker is ready. An alarm limits a failed test.
static volatile sig_atomic_t done = 0;
static void finish(int signal) { (void)signal; done = 1; }

int main(void) {
    int ready[2];
    if (pipe(ready) != 0) return 1;
    pid_t worker = fork();
    if (worker < 0) return 1;
    if (worker == 0) {
        signal(SIGTERM, finish);
        alarm(30);
        close(ready[0]);
        if (write(ready[1], "r", 1) != 1) return 2;
        close(ready[1]);
        while (!done) pause();
        return 0;
    }
    signal(SIGINT, finish);
    alarm(30);
    close(ready[1]);
    char byte;
    if (read(ready[0], &byte, 1) != 1) return 3;
    close(ready[0]);
    printf("%d\n", worker);
    fflush(stdout);
    while (!done) pause();
    kill(worker, SIGTERM);
    int status = 0;
    if (waitpid(worker, &status, 0) != worker) return 4;
    return 0;
}
