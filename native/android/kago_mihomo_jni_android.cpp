#include <jni.h>

#include <cstring>
#include <mutex>
#include <shared_mutex>
#include <string>

#include "kago_mihomo_bridge.h"

namespace {
JavaVM* g_vm = nullptr;
// Readers (protect/resolve calls from core threads) run in parallel; start and
// release take it exclusively.
std::shared_mutex g_service_mutex;
jobject g_vpn_service = nullptr;
jmethodID g_protect_method = nullptr;
jmethodID g_resolve_method = nullptr;

void release_service(JNIEnv* env) {
  std::lock_guard<std::shared_mutex> lock(g_service_mutex);
  if (g_vpn_service != nullptr) {
    env->DeleteGlobalRef(g_vpn_service);
    g_vpn_service = nullptr;
  }
  g_protect_method = nullptr;
  g_resolve_method = nullptr;
}

int protect_socket(int socket_fd) {
  if (g_vm == nullptr) return 0;

  JNIEnv* env = nullptr;
  bool attached_here = false;
  const jint status = g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
  if (status == JNI_EDETACHED) {
    if (g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) return 0;
    attached_here = true;
  } else if (status != JNI_OK) {
    return 0;
  }

  jboolean accepted = JNI_FALSE;
  {
    std::shared_lock<std::shared_mutex> lock(g_service_mutex);
    if (g_vpn_service != nullptr && g_protect_method != nullptr) {
      accepted = env->CallBooleanMethod(g_vpn_service, g_protect_method, static_cast<jint>(socket_fd));
      if (env->ExceptionCheck()) {
        env->ExceptionClear();
        accepted = JNI_FALSE;
      }
    }
  }

  if (attached_here) g_vm->DetachCurrentThread();
  return accepted == JNI_TRUE ? 1 : 0;
}

// KaGoVpnService.resolvePackage(protocol, srcIp, srcPort, dstIp, dstPort): the
// package that owns the connection, for PROCESS-NAME rules.
int resolve_package(int protocol, const char* src_ip, int src_port, const char* dst_ip, int dst_port,
                    char* out, int out_len) {
  if (g_vm == nullptr || out == nullptr || out_len <= 1) return 0;

  JNIEnv* env = nullptr;
  bool attached_here = false;
  const jint status = g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
  if (status == JNI_EDETACHED) {
    if (g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) return 0;
    attached_here = true;
  } else if (status != JNI_OK) {
    return 0;
  }

  int length = 0;
  jstring src = env->NewStringUTF(src_ip == nullptr ? "" : src_ip);
  jstring dst = env->NewStringUTF(dst_ip == nullptr ? "" : dst_ip);
  if (src != nullptr && dst != nullptr) {
    jobject result = nullptr;
    {
      std::shared_lock<std::shared_mutex> lock(g_service_mutex);
      if (g_vpn_service != nullptr && g_resolve_method != nullptr) {
        result = env->CallObjectMethod(g_vpn_service, g_resolve_method, static_cast<jint>(protocol), src,
                                       static_cast<jint>(src_port), dst, static_cast<jint>(dst_port));
        if (env->ExceptionCheck()) {
          env->ExceptionClear();
          result = nullptr;
        }
      }
    }
    if (result != nullptr) {
      const char* chars = env->GetStringUTFChars(static_cast<jstring>(result), nullptr);
      if (chars != nullptr) {
        const size_t size = std::strlen(chars);
        if (size > 0 && size < static_cast<size_t>(out_len)) {
          std::memcpy(out, chars, size + 1);
          length = static_cast<int>(size);
        }
        env->ReleaseStringUTFChars(static_cast<jstring>(result), chars);
      }
      env->DeleteLocalRef(result);
    }
  }
  if (src != nullptr) env->DeleteLocalRef(src);
  if (dst != nullptr) env->DeleteLocalRef(dst);

  if (attached_here) g_vm->DetachCurrentThread();
  return length;
}

bool copy_string(JNIEnv* env, jstring input, std::string* output) {
  if (input == nullptr) return false;
  const char* chars = env->GetStringUTFChars(input, nullptr);
  if (chars == nullptr) return false;
  output->assign(chars);
  env->ReleaseStringUTFChars(input, chars);
  return true;
}
}  // namespace

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  g_vm = vm;
  return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT jint JNICALL
Java_net_usekago_app_MihomoNativeCore_start(JNIEnv* env, jobject, jobject vpn_service,
                                            jstring config_path, jstring work_dir, jint tun_fd, jint mtu,
                                            jstring stack, jstring tunnel_address, jstring tunnel_dns) {
  std::string config;
  std::string directory;
  std::string stack_value;
  std::string address_value;
  std::string dns_value;
  if (!copy_string(env, config_path, &config) || !copy_string(env, work_dir, &directory) ||
      !copy_string(env, stack, &stack_value) || !copy_string(env, tunnel_address, &address_value) ||
      !copy_string(env, tunnel_dns, &dns_value) || vpn_service == nullptr) {
    return -1;
  }

  jobject service_ref = env->NewGlobalRef(vpn_service);
  if (service_ref == nullptr) return -2;
  jclass service_class = env->GetObjectClass(vpn_service);
  jmethodID protect_method = service_class == nullptr ? nullptr : env->GetMethodID(service_class, "protect", "(I)Z");
  // No JNI call may run with an exception pending: settle the protect lookup
  // before looking up resolvePackage.
  if (protect_method == nullptr || env->ExceptionCheck()) {
    env->ExceptionClear();
    if (service_class != nullptr) env->DeleteLocalRef(service_class);
    env->DeleteGlobalRef(service_ref);
    return -3;
  }
  // Optional: without it PROCESS-NAME rules simply do not match.
  jmethodID resolve_method = service_class == nullptr
                                 ? nullptr
                                 : env->GetMethodID(service_class, "resolvePackage",
                                                    "(ILjava/lang/String;ILjava/lang/String;I)Ljava/lang/String;");
  if (resolve_method == nullptr) env->ExceptionClear();
  if (service_class != nullptr) env->DeleteLocalRef(service_class);
  if (protect_method == nullptr || env->ExceptionCheck()) {
    env->ExceptionClear();
    env->DeleteGlobalRef(service_ref);
    return -3;
  }

  {
    std::lock_guard<std::shared_mutex> lock(g_service_mutex);
    if (g_vpn_service != nullptr) {
      env->DeleteGlobalRef(service_ref);
      return -4;
    }
    g_vpn_service = service_ref;
    g_protect_method = protect_method;
    g_resolve_method = resolve_method;
  }
  if (kago_mihomo_set_socket_protector(&protect_socket) != 0) {
    release_service(env);
    return -5;
  }
  kago_mihomo_set_package_resolver(resolve_method != nullptr ? &resolve_package : nullptr);

  const int result = kago_mihomo_start_with_tun_fd(
      const_cast<char*>(config.c_str()), const_cast<char*>(directory.c_str()),
      static_cast<int>(tun_fd), static_cast<int>(mtu),
      const_cast<char*>(stack_value.c_str()), const_cast<char*>(address_value.c_str()),
      const_cast<char*>(dns_value.c_str()));
  if (result != 0) {
    // The core contract requires start failure to join workers and release any duplicated TUN fd.
    kago_mihomo_stop();
    kago_mihomo_set_socket_protector(nullptr);
    kago_mihomo_set_package_resolver(nullptr);
    release_service(env);
  }
  return static_cast<jint>(result);
}

extern "C" JNIEXPORT jint JNICALL
Java_net_usekago_app_MihomoNativeCore_stop(JNIEnv* env, jobject) {
  // stop() must synchronously join core workers before the callback target is released.
  const int result = kago_mihomo_stop();
  kago_mihomo_set_socket_protector(nullptr);
  kago_mihomo_set_package_resolver(nullptr);
  release_service(env);
  return static_cast<jint>(result);
}

extern "C" JNIEXPORT jstring JNICALL
Java_net_usekago_app_MihomoNativeCore_version(JNIEnv* env, jobject) {
  char* version = kago_mihomo_version();
  jstring result = env->NewStringUTF(version == nullptr ? "" : version);
  if (version != nullptr) kago_mihomo_free_string(version);
  return result;
}

extern "C" JNIEXPORT jstring JNICALL
Java_net_usekago_app_MihomoNativeCore_lastError(JNIEnv* env, jobject) {
  char* message = kago_mihomo_last_error();
  jstring result = env->NewStringUTF(message == nullptr ? "" : message);
  if (message != nullptr) kago_mihomo_free_string(message);
  return result;
}
