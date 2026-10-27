#include "adas_protocol.h"
#include <string.h>

static uint16_t u16(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

uint16_t adas_crc16(const uint8_t *data, size_t size) {
    uint16_t crc = 0xffffu;
    size_t i;
    unsigned bit;
    for (i = 0; i < size; ++i) {
        crc ^= (uint16_t)((uint16_t)data[i] << 8);
        for (bit = 0; bit < 8; ++bit)
            crc = (uint16_t)((crc & 0x8000u) ? ((uint32_t)crc << 1) ^ 0x1021u : (uint32_t)crc << 1);
    }
    return crc;
}

void adas_decoder_init(adas_decoder *d) { memset(d, 0, sizeof(*d)); }

static void discard_first(adas_decoder *d) {
    --d->count;
    memmove(d->buffer, d->buffer + 1, d->count);
}

static int decode_payload(const uint8_t *p, adas_observation *out) {
    adas_observation o;
    uint16_t values[13], raw_offset;
    uint8_t lk, rk, warning;
    unsigned i;
    memset(&o, 0, sizeof(o));
    o.flags = p[0]; o.types = p[1]; o.frame_id = u16(p + 2);
    raw_offset = u16(p + 4);
    o.offset_px = (int16_t)(raw_offset <= 32767u ? (int32_t)raw_offset : (int32_t)raw_offset - 65536);
    for (i = 0; i < 13; ++i) {
        values[i] = u16(p + 6 + 2 * i);
        if (values[i] > 2047u) return 0;
    }
    o.lane_width = values[0];
    o.left.x0 = values[1]; o.left.y0 = values[2]; o.left.x1 = values[3]; o.left.y1 = values[4];
    o.right.x0 = values[5]; o.right.y0 = values[6]; o.right.x1 = values[7]; o.right.y1 = values[8];
    o.left_support = values[9]; o.right_support = values[10]; o.zebra_y0 = values[11]; o.zebra_y1 = values[12];
    lk = o.types & 3u; rk = (o.types >> 2) & 3u; warning = (o.types >> 4) & 3u;
    if ((o.flags & 0x80u) || !(o.flags & ADAS_EXPERIMENTAL) || (o.types & 0xc0u)) return 0;
    if (lk > 2u || rk > 2u || warning > 2u || o.offset_px < -2048 || o.offset_px > 2047) return 0;
    if ((o.flags & ADAS_ZEBRA_CONFIRMED) && !(o.flags & ADAS_ZEBRA_CANDIDATE)) return 0;
    if ((o.flags & ADAS_MALFORMED_FRAME) && ((o.flags & 0x1fu) || o.types)) return 0;
    if (o.flags & ADAS_PAIR_VALID) {
        if ((o.flags & 3u) != 3u || o.right.x1 <= o.left.x1 || o.lane_width != o.right.x1 - o.left.x1) return 0;
    } else if (o.offset_px || o.lane_width || warning) return 0;
    if (o.flags & ADAS_LEFT_VALID) {
        if (o.left.y1 <= o.left.y0) return 0;
    } else if (lk || o.left.x0 || o.left.y0 || o.left.x1 || o.left.y1) return 0;
    if (o.flags & ADAS_RIGHT_VALID) {
        if (o.right.y1 <= o.right.y0) return 0;
    } else if (rk || o.right.x0 || o.right.y0 || o.right.x1 || o.right.y1) return 0;
    if (o.flags & ADAS_ZEBRA_CANDIDATE) {
        if (o.zebra_y0 > o.zebra_y1) return 0;
    } else if (o.zebra_y0 || o.zebra_y1) return 0;
    *out = o;
    return 1;
}

int adas_decoder_feed(adas_decoder *d, uint8_t byte, adas_observation *out) {
    d->buffer[d->count++] = byte;
    while (d->count) {
        if (d->buffer[0] != 0xa5u || (d->count >= 2u && d->buffer[1] != 0x5au)) {
            discard_first(d);
            continue;
        }
        if (d->count < 4u) return 0;
        if (d->buffer[2] != 1u || d->buffer[3] != 32u) {
            ++d->invalid_packets;
            discard_first(d);
            continue;
        }
        if (d->count < ADAS_PACKET_SIZE) return 0;
        if (adas_crc16(d->buffer + 2, 34) != u16(d->buffer + 36)) {
            ++d->crc_errors;
            discard_first(d);
            continue;
        }
        d->count = 0;
        if (decode_payload(d->buffer + 4, out)) return 1;
        ++d->invalid_packets;
    }
    return 0;
}

int adas_is_fresh(const adas_freshness *s, uint32_t now_ms, uint32_t timeout_ms) {
    return timeout_ms && timeout_ms < 0x80000000u && s->seen && (uint32_t)(now_ms - s->received_ms) <= timeout_ms;
}

int adas_accept_frame(adas_freshness *s, uint16_t frame_id, uint32_t now_ms, uint32_t timeout_ms) {
    uint16_t delta;
    if (!timeout_ms || timeout_ms >= 0x80000000u) return 0;
    if (adas_is_fresh(s, now_ms, timeout_ms)) {
        delta = (uint16_t)(frame_id - s->frame_id);
        if (!delta || delta >= 0x8000u) return 0;
    }
    s->seen = 1; s->frame_id = frame_id; s->received_ms = now_ms;
    return 1;
}
