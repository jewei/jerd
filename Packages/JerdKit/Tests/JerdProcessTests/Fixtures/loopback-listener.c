#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

// Test fixture only. Listens on 127.0.0.1 with an ephemeral port and prints the port.
// With "udp", it also opens a UDP socket on 127.0.0.1. No other network work.
int main(int argc, char **argv) {
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    memset(&address, 0, sizeof address);
    address.sin_len = sizeof address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (listener < 0 || bind(listener, (struct sockaddr *)&address, sizeof address) != 0) return 2;
    if (listen(listener, 1) != 0) return 3;
    socklen_t length = sizeof address;
    getsockname(listener, (struct sockaddr *)&address, &length);
    if (argc > 1 && strcmp(argv[1], "udp") == 0) {
        int datagram = socket(AF_INET, SOCK_DGRAM, 0);
        struct sockaddr_in local;
        memset(&local, 0, sizeof local);
        local.sin_len = sizeof local;
        local.sin_family = AF_INET;
        local.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        if (datagram < 0 || bind(datagram, (struct sockaddr *)&local, sizeof local) != 0) return 4;
    }
    printf("%d\n", ntohs(address.sin_port));
    fflush(stdout);
    sleep(30); // Fail-safe end if a test cannot stop the fixture.
    return 0;
}
