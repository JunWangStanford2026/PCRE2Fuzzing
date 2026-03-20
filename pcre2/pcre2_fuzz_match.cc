#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <vector>
#include <algorithm>

#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#define MAX_PATTERN_SIZE 8192
#define MAX_SUBJECT_SIZE 1024

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 3) {
        return 0;
    }

    size_t pattern_len = *(uint16_t*)data % MAX_PATTERN_SIZE;
    if (pattern_len + 2 >= size) {
        return 0;
    }

    size_t subject_len = size - pattern_len - 2;
    if (subject_len > MAX_SUBJECT_SIZE) {
        subject_len = MAX_SUBJECT_SIZE;
    }

    const uint8_t *pattern = data + 2;
    const uint8_t *subject = data + 2 + pattern_len;

    int errorcode;
    PCRE2_SIZE erroroffset;

    pcre2_code *re = pcre2_compile(
        pattern,
        pattern_len,
        0,  // removed UTF flag
        &errorcode,
        &erroroffset,
        NULL
    );

    if (re == NULL) {
        return 0;
    }

    pcre2_match_data *match_data =
        pcre2_match_data_create_from_pattern(re, NULL);

    if (match_data == NULL) {
        pcre2_code_free(re);
        return 0;
    }

    pcre2_match(
        re,
        subject,
        subject_len,
        0,
        0,
        match_data,
        NULL
    );

    pcre2_match_data_free(match_data);
    pcre2_code_free(re);

    return 0;
}