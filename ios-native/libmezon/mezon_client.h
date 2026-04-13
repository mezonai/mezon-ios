#ifndef MEZON_PROTO_CLIENT
#define MEZON_PROTO_CLIENT

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct mezon_session mezon_session_t;

typedef void (*mezon_transmit_fn)(const uint8_t *data, size_t len, void *userdata);

typedef void (*mezon_on_data_fn)(int64_t stream_id, const uint8_t *data, size_t len, bool fin, void *userdata);

typedef struct mezon_config {
  const char *host;
  const char *alpn;

  mezon_transmit_fn transmit_cb;
  mezon_on_data_fn data_cb;

  void *userdata;

  const struct sockaddr *local_addr;
  socklen_t local_addrlen;

  const struct sockaddr *remote_addr;
  socklen_t remote_addrlen;
} mezon_config_t;

mezon_session_t *mezon_create(const mezon_config_t *cfg, uint64_t now_ns);
void mezon_destroy(mezon_session_t *s);

void mezon_feed_network(mezon_session_t *s, const uint8_t *data, size_t len, const struct sockaddr *local, const struct sockaddr *remote);

int mezon_send(mezon_session_t *s, int64_t stream_id, const uint8_t *data, size_t len, bool fin);

int64_t mezon_open_api_stream(mezon_session_t *s);

#ifdef __cplusplus
}
#endif

#endif