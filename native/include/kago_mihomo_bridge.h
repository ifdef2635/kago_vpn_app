#ifndef KAGO_MIHOMO_BRIDGE_H
#define KAGO_MIHOMO_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

/* Stable C ABI implemented by the Android c-shared Mihomo bridge. */
int kago_mihomo_start(char *config_path, char *work_dir);
/* Android JNI wrapper registers VpnService.protect(int) for outbound core sockets. */
typedef int (*kago_socket_protector)(int socket_fd);
int kago_mihomo_set_socket_protector(kago_socket_protector protector);
int kago_mihomo_protect_socket(int socket_fd);
/* The Go bridge duplicates tun_fd before success; Android owns routing and MTU. */
int kago_mihomo_start_with_tun_fd(char *config_path, char *work_dir, int tun_fd,
                                  int mtu, char *stack, char *tunnel_address,
                                  char *tunnel_dns);
int kago_mihomo_stop(void);
int kago_mihomo_is_running(void);
/* Returned strings are heap-allocated and must be freed with kago_mihomo_free_string. */
char *kago_mihomo_version(void);
char *kago_mihomo_last_error(void);
void kago_mihomo_free_string(char *value);

#ifdef __cplusplus
}
#endif
#endif
