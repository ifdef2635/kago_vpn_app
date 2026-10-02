#ifndef KAGO_SOCKET_PROTECTOR_H
#define KAGO_SOCKET_PROTECTOR_H

#include "kago_mihomo_bridge.h"

void kago_store_socket_protector(kago_socket_protector protector);
int kago_call_socket_protector(int socket_fd);

#endif
