#include "kago_socket_protector.h"

#include <stdatomic.h>

static _Atomic(kago_socket_protector) g_protector = NULL;

void kago_store_socket_protector(kago_socket_protector protector) {
  atomic_store_explicit(&g_protector, protector, memory_order_release);
}

int kago_call_socket_protector(int socket_fd) {
  kago_socket_protector protector = atomic_load_explicit(&g_protector, memory_order_acquire);
  if (protector == NULL) return 0;
  return protector(socket_fd);
}
