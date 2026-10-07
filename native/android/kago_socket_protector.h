#ifndef KAGO_SOCKET_PROTECTOR_H
#define KAGO_SOCKET_PROTECTOR_H

#include "kago_mihomo_bridge.h"

void kago_store_socket_protector(kago_socket_protector protector);
int kago_call_socket_protector(int socket_fd);

void kago_store_package_resolver(kago_package_resolver resolver);
int kago_call_package_resolver(int protocol, const char *src_ip, int src_port,
                               const char *dst_ip, int dst_port, char *out, int out_len);

#endif
