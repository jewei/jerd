#include <stdio.h>
#include <string.h>

int main(void) {
    char data[4096];
    memset(data, 'x', sizeof(data));
    puts("first-output");
    for (int i = 0; i < 2600; i++) fwrite(data, 1, sizeof(data), stdout);
    puts("\nlast-failure-detail");
    return 7;
}
