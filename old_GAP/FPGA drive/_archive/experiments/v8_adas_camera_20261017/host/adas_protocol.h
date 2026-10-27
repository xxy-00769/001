#ifndef ADAS_PROTOCOL_H
#define ADAS_PROTOCOL_H
#include <stdint.h>
#include <stddef.h>

#define ADAS_PACKET_SIZE 38u
#define ADAS_LEFT_VALID 0x01u
#define ADAS_RIGHT_VALID 0x02u
#define ADAS_PAIR_VALID 0x04u
#define ADAS_ZEBRA_CANDIDATE 0x08u
#define ADAS_ZEBRA_CONFIRMED 0x10u
#define ADAS_MALFORMED_FRAME 0x20u
#define ADAS_EXPERIMENTAL 0x40u

typedef struct { uint16_t x0, y0, x1, y1; } adas_line;
typedef struct {
    uint8_t flags, types;
    uint16_t frame_id;
    int16_t offset_px;
    uint16_t lane_width;
    adas_line left, right;
    uint16_t left_support, right_support, zebra_y0, zebra_y1;
} adas_observation;

typedef struct {
    uint8_t buffer[ADAS_PACKET_SIZE];
    uint8_t count;
    uint32_t crc_errors, invalid_packets;
} adas_decoder;

typedef struct {
    uint32_t received_ms;
    uint16_t frame_id;
    uint8_t seen;
} adas_freshness;

uint16_t adas_crc16(const uint8_t *data, size_t size);
void adas_decoder_init(adas_decoder *decoder);
/* Returns 1 only when out receives a complete, CRC-checked valid observation. */
int adas_decoder_feed(adas_decoder *decoder, uint8_t byte, adas_observation *out);
/* timeout_ms must be nonzero and below 2^31; unsigned tick rollover is supported. */
int adas_is_fresh(const adas_freshness *state, uint32_t now_ms, uint32_t timeout_ms);
int adas_accept_frame(adas_freshness *state, uint16_t frame_id, uint32_t now_ms, uint32_t timeout_ms);
#endif
