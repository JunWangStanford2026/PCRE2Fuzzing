#include <stdint.h>
#include <string.h>

int toy_bug(const uint8_t *data, size_t size) {
    char buffer[32];

    if (size == 0) {
        return -10;
    }

    if (data[0] == 'X') {
        if (size < 30) {
            memcpy(buffer, data, size);
            buffer[31] = '\0';
            return -1;
        }
    }

    if (size > 0) {
        memcpy(buffer, data, size); // doesn't check if size less than buffer
        buffer[31] = '\0';
    }
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    toy_bug(data, size);
    return 0;
}