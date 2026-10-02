#include <jni.h>

#include <mutex>
#include <string>

#include "kago_mihomo_bridge.h"

namespace {
JavaVM* g_vm = nullptr;
std::mutex g_service_mutex;
jobject g_vpn_service = nullptr;
jmethodID g_protect_method = nullptr;

void release_service(JNIEnv* env) {
  std::lock_guard<std::mutex> lock(g_service_mutex);
  if (g_vpn_service != nullptr) {
    env->DeleteGlobalRef(g_vpn_service);
    g_vpn_service = nullptr;
  }
  g_protect_method = nullptr;
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
    std::lock_guard<std::mutex> lock(g_service_mutex);
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
Java_net_usekago_vpn_MihomoNativeCore_start(JNIEnv* env, jobject, jobject vpn_service,
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
  if (service_class != nullptr) env->DeleteLocalRef(service_class);
  if (protect_method == nullptr || env->ExceptionCheck()) {
    env->ExceptionClear();
    env->DeleteGlobalRef(service_ref);
    return -3;
  }

  {
    std::lock_guard<std::mutex> lock(g_service_mutex);
    if (g_vpn_service != nullptr) {
      env->DeleteGlobalRef(service_ref);
      return -4;
    }
    g_vpn_service = service_ref;
    g_protect_method = protect_method;
  }
  if (kago_mihomo_set_socket_protector(&protect_socket) != 0) {
    release_service(env);
    return -5;
  }

  const int result = kago_mihomo_start_with_tun_fd(
      const_cast<char*>(config.c_str()), const_cast<char*>(directory.c_str()),
      static_cast<int>(tun_fd), static_cast<int>(mtu),
      const_cast<char*>(stack_value.c_str()), const_cast<char*>(address_value.c_str()),
      const_cast<char*>(dns_value.c_str()));
  if (result != 0) {
    // The core contract requires start failure to join workers and release any duplicated TUN fd.
    kago_mihomo_stop();
    kago_mihomo_set_socket_protector(nullptr);
    release_service(env);
  }
  return static_cast<jint>(result);
}

extern "C" JNIEXPORT jint JNICALL
Java_net_usekago_vpn_MihomoNativeCore_stop(JNIEnv* env, jobject) {
  // stop() must synchronously join core workers before the callback target is released.
  const int result = kago_mihomo_stop();
  kago_mihomo_set_socket_protector(nullptr);
  release_service(env);
  return static_cast<jint>(result);
}

extern "C" JNIEXPORT jstring JNICALL
Java_net_usekago_vpn_MihomoNativeCore_version(JNIEnv* env, jobject) {
  char* version = kago_mihomo_version();
  jstring result = env->NewStringUTF(version == nullptr ? "" : version);
  if (version != nullptr) kago_mihomo_free_string(version);
  return result;
}

extern "C" JNIEXPORT jstring JNICALL
Java_net_usekago_vpn_MihomoNativeCore_lastError(JNIEnv* env, jobject) {
  char* message = kago_mihomo_last_error();
  jstring result = env->NewStringUTF(message == nullptr ? "" : message);
  if (message != nullptr) kago_mihomo_free_string(message);
  return result;
}
