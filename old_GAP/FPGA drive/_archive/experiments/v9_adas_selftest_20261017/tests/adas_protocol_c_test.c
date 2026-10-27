#include "../host/adas_protocol.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    FILE *file;
    uint8_t input[4096], corrupt[38];
    size_t size, i;
    unsigned count = 0, bit;
    adas_decoder decoder;
    adas_observation result;
    adas_freshness freshness = {0, 0, 0};
    assert(argc == 2);
    file = fopen(argv[1], "rb");
    assert(file);
    size = fread(input, 1, sizeof(input), file);
    assert(!ferror(file) && feof(file));
    fclose(file);
    assert(size >= 38 && size % 38 == 0);
    assert(adas_crc16((const uint8_t *)"123456789", 9) == 0x29b1u);
    adas_decoder_init(&decoder);
    for (i = 0; i < size; ++i) count += adas_decoder_feed(&decoder, input[i], &result);
    assert(count == size / 38 && !decoder.crc_errors && !decoder.invalid_packets && !decoder.count);
    for (bit = 0; bit < 304; ++bit) {
        memcpy(corrupt, input, 38);
        corrupt[bit / 8] ^= (uint8_t)(1u << (bit % 8));
        adas_decoder_init(&decoder);
        count = 0;
        for (i = 0; i < 38; ++i) count += adas_decoder_feed(&decoder, corrupt[i], &result);
        for (i = 0; i < 38; ++i) count += adas_decoder_feed(&decoder, input[i], &result);
        assert(count == 1);
    }
    assert(adas_accept_frame(&freshness, 65535, 0, 500));
    assert(adas_accept_frame(&freshness, 0, 100, 500));
    assert(!adas_accept_frame(&freshness, 0, 200, 500));
    assert(!adas_accept_frame(&freshness, 65535, 300, 500));
    assert(!adas_is_fresh(&freshness, 700, 500));
    assert(adas_accept_frame(&freshness, 1, 800, 500));
    freshness.received_ms = 0xfffffff0u;
    assert(adas_is_fresh(&freshness, 10, 500));
    assert(!adas_is_fresh(&freshness, 600, 500));
    assert(!adas_accept_frame(&freshness, 2, 1000, 0));
    printf("PASS: C decoder %u packets, 304 single-bit corruptions, CRC, sequence/time rollover and freshness\n", (unsigned)(size / 38));
    return 0;
}
