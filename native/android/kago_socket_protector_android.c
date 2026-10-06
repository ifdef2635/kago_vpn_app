#include "kago_socket_protector.h"

#include <stdatomic.h>
#include <stddef.h>

static _Atomic(kago_socket_protector) g_protector = NULL;

void kago_store_socket_protector(kago_socket_protector protector) {
  atomic_store_explicit(&g_protector, protector, memory_order_release);
}

int kago_call_socket_protector(int socket_fd) {
  kago_socket_protector protector = atomic_load_explicit(&g_protector, memory_order_acquire);
  if (protector == NULL) return 0;
  return protector(socket_fd);
}

static _Atomic(kago_package_resolver) g_package_resolver = NULL;

void kago_store_package_resolver(kago_package_resolver resolver) {
  atomic_store_explicit(&g_package_resolver, resolver, memory_order_release);
}

int kago_call_package_resolver(int protocol, const char *src_ip, int src_port,
                               const char *dst_ip, int dst_port, char *out, int out_len) {
  kago_package_resolver resolver = atomic_load_explicit(&g_package_resolver, memory_order_acquire);
  if (resolver == NULL || out == NULL || out_len <= 0) return 0;
  return resolver(protocol, src_ip, src_port, dst_ip, dst_port, out, out_len);
}
