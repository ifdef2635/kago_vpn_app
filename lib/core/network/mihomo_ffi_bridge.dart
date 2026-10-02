import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Thin FFI loader for the ABI in native/include/kago_mihomo_bridge.h.
/// The per-platform shared library must be built and bundled by the host app.
class MihomoFfiBridge {
  MihomoFfiBridge._(DynamicLibrary library)
      : _start = library
            .lookupFunction<_StartNative, _StartDart>('kago_mihomo_start'),
        _stop =
            library.lookupFunction<_StopNative, _StopDart>('kago_mihomo_stop'),
        _isRunning = library.lookupFunction<_RunningNative, _RunningDart>(
            'kago_mihomo_is_running'),
        _version = library.lookupFunction<_VersionNative, _VersionDart>(
            'kago_mihomo_version');
  final _StartDart _start;
  final _StopDart _stop;
  final _RunningDart _isRunning;
  final _VersionDart _version;

  static MihomoFfiBridge open() {
    final library = switch (Platform.operatingSystem) {
      'android' => DynamicLibrary.open('libkago_mihomo_bridge.so'),
      'ios' => DynamicLibrary.process(),
      'macos' => DynamicLibrary.open('libkago_mihomo_bridge.dylib'),
      'windows' => DynamicLibrary.open('kago_mihomo_bridge.dll'),
      'linux' => DynamicLibrary.open('libkago_mihomo_bridge.so'),
      _ => throw UnsupportedError(
          'Mihomo FFI не поддерживается на ${Platform.operatingSystem}.'),
    };
    return MihomoFfiBridge._(library);
  }

  int start({required String configPath, required String workDirectory}) {
    final nativeConfig = configPath.toNativeUtf8();
    final nativeWork = workDirectory.toNativeUtf8();
    try {
      return _start(nativeConfig, nativeWork);
    } finally {
      malloc.free(nativeConfig);
      malloc.free(nativeWork);
    }
  }

  int stop() => _stop();
  bool get isRunning => _isRunning() != 0;
  String get version => _version().toDartString();
}

typedef _StartNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _StartDart = int Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _StopNative = Int32 Function();
typedef _StopDart = int Function();
typedef _RunningNative = Int32 Function();
typedef _RunningDart = int Function();
typedef _VersionNative = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();
