#include "mezon_client.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <winsock2.h>
#else
#include <arpa/inet.h>
#endif

struct mezon_session {
  mezon_config_t cfg;
  uint8_t read_buf[65535];
  size_t read_pos;
};

mezon_session_t *mezon_create(const mezon_config_t *cfg, uint64_t now_ns) {
  fprintf(stderr, "   [C-CORE] Creating Mezon TCP Abridged Session\n");

  mezon_session_t *s = calloc(1, sizeof(*s));
  if (!s) {
    return NULL;
  }

  s->cfg = *cfg;

  uint8_t magic = 0xef;
  s->cfg.transmit_cb(&magic, 1, s->cfg.userdata);

  return s;
}

void mezon_feed_network(mezon_session_t *s, const uint8_t *data, size_t len, const struct sockaddr *local, const struct sockaddr *remote) {
  /*
    MEZON ABRIDGED PROTOCOL PARSING:
    Typically: [Length Byte (1 or 4 bytes)] [Payload]
    If Length < 0x7f, it's 1 byte. If 0x7f, next 3 bytes are length.
  */

  if (s->cfg.data_cb) {
    s->cfg.data_cb(0, data, len, false, s->cfg.userdata);
  }
}

/*
  Sends data over TCP using Abridged Framing:
  Length is (total_len / 4).
*/
int mezon_send(mezon_session_t *s, int64_t stream_id, const uint8_t *data, size_t len, bool fin) {
  if (len == 0) {
    return 0;
  }

  // Allocate buffer for [Abridged Header] + [Data]
  // Abridged Header is usually 1 byte if len/4 < 127
  uint8_t header[4];
  size_t header_size = 0;

  uint32_t len_div = (uint32_t)(len / 4);

  if (len_div < 0x7f) {
    header[0] = (uint8_t)len_div;
    header_size = 1;
  } else {
    header[0] = 0x7f;
    header[1] = (uint8_t)(len_div & 0xff);
    header[2] = (uint8_t)((len_div >> 8) & 0xff);
    header[3] = (uint8_t)((len_div >> 16) & 0xff);
    header_size = 4;
  }

  // Send header
  s->cfg.transmit_cb(header, header_size, s->cfg.userdata);

  // Send payload
  s->cfg.transmit_cb(data, len, s->cfg.userdata);

  return 0;
}