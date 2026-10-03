import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'mihomo_controller.dart';
import 'mihomo_windows_core_updater.dart';
import 'mihomo_windows_system_proxy.dart';

/// Desktop lifecycle for built-in Windows Mihomo or an optional user-supplied executable.
class MihomoProcessManager {
  MihomoProcessManager({
    MihomoWindowsCoreUpdater? coreUpdater,
    MihomoWindowsSystemProxy? windowsSystemProxy,
  })  : _coreUpdater = coreUpdater ?? MihomoWindowsCoreUpdater(),
        _windowsSystemProxy = windowsSystemProxy ?? MihomoWindowsSystemProxy();

  static const _binaryKey = 'mihomo.binary';
  final MihomoWindowsCoreUpdater _coreUpdater;
  final MihomoWindowsSystemProxy _windowsSystemProxy;
  Process? _process;
  StreamSubscription<String>? _stdout;
  StreamSubscription<String>? _stderr;
  final StreamController<String> _logs = StreamController<String>.broadcast();
  final List<String> _recentLogs = <String>[];
  final StreamController<int> _exits = StreamController<int>.broadcast();

  /// Emits the exit code when the core stops on its own (crash, killed from
  /// outside). Not emitted for a normal [stop].
  Stream<int> get exits => _exits.stream;

  bool get isRunning => _process != null;
  Stream<String> get logs => _logs.stream;
  List<String> get recentLogs => List<String>.unmodifiable(_recentLogs);

  void _writeLog(String line) {
    _recentLogs.add(line);
    if (_recentLogs.length > 100) _recentLogs.removeAt(0);
    if (!_logs.isClosed) _logs.add(line);
  }

  /// Last core output lines, so a failed start explains itself (the log panel
  /// in settings is only shown while the core is running).
  String _logTail([int lines = 6]) {
    if (_recentLogs.isEmpty) return '';
    final tail = _recentLogs.length > lines
        ? _recentLogs.sublist(_recentLogs.length - lines)
        : _recentLogs;
    return '\nЛог ядра:\n${tail.join('\n')}';
  }

  /// Manual core path. Only Linux/macOS use it (they have no built-in core);
  /// on Windows the core is always the managed one, so a path saved by an
  /// older version is dropped instead of silently overriding it.
  Future<String?> get executable async {
    final prefs = await SharedPreferences.getInstance();
    if (Platform.isWindows) {
      if (prefs.containsKey(_binaryKey)) await prefs.remove(_binaryKey);
      return null;
    }
    return prefs.getString(_binaryKey);
  }

  Future<void> saveExecutable(String path) async {
    if (Platform.isWindows) return;
    final value = path.trim();
    final prefs = await SharedPreferences.getInstance();
    if (value.isEmpty) {
      await prefs.remove(_binaryKey);
    } else {
      await prefs.setString(_binaryKey, value);
    }
  }

  Future<MihomoCoreInstall?> installedCore() => _coreUpdater.installed();

  /// Downloads or updates the managed Windows core in the background so it is
  /// ready before the first connection. Failures are logged, never thrown.
  Future<void> prepareCore() async {
    if (!Platform.isWindows) return;
    try {
      final core = await _coreUpdater.ensureInstalled(onLog: _writeLog);
      _writeLog('Встроенный Mihomo ${core.version} готов.');
    } catch (error) {
      _writeLog('Автозагрузка ядра не удалась: $error');
    }
  }

  Future<void> recoverStaleSystemProxy() async {
    try {
      await _windowsSystemProxy.restoreIfOwned();
    } catch (error) {
      _writeLog('Не удалось восстановить сохранённые proxy settings: $error');
    }
  }

  Future<MihomoCoreInstall> updateCore() async {
    if (_process != null) {
      throw StateError(
          'Остановите Mihomo перед проверкой/установкой обновления.');
    }
    return _coreUpdater.ensureInstalled(forceCheck: true, onLog: _writeLog);
  }

  Future<void> start({required String configPath}) async {
    if (_process != null) return;
    final overridePath = (await executable)?.trim() ?? '';
    final usingOverride = overridePath.isNotEmpty;
    final String binary;
    if (usingOverride) {
      binary = overridePath;
    } else if (Platform.isWindows) {
      final core = await _coreUpdater.ensureInstalled(onLog: _writeLog);
      binary = core.executable.path;
      _writeLog('Запускается встроенный Mihomo ${core.version}.');
    } else {
      throw StateError(
          'Для этой desktop-платформы укажите путь к Mihomo в настройках.');
    }
    if (!await File(binary).exists()) {
      throw FileSystemException(
          usingOverride
              ? 'Файл Mihomo из настроек не найден. Исправьте путь или очистите поле, чтобы использовать встроенное ядро'
              : 'Встроенный Mihomo не найден на диске. Нажмите «Проверить и установить обновление» в настройках',
          binary);
    }
    if (!await File(configPath).exists()) {
      throw FileSystemException(
          'Сначала импортируйте YAML-подписку', configPath);
    }

    final controller = MihomoController(
      connectTimeout: const Duration(milliseconds: 500),
      receiveTimeout: const Duration(seconds: 1),
    );
    final controllerUri = Uri.parse(await controller.endpoint);
    if (controllerUri.scheme != 'http' ||
        !<String>['127.0.0.1', 'localhost', '::1']
            .contains(controllerUri.host)) {
      throw StateError(
          'Desktop core запускается с локальным HTTP controller. Укажите http://127.0.0.1:<port>.');
    }
    final configFile = File(configPath);
    final Object? decoded = jsonDecode(await configFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Активная конфигурация Mihomo повреждена.');
    }
    final config = decoded;
    if (Platform.isWindows) {
      config['mixed-port'] = 7890;
      final tunValue = config['tun'];
      final tun =
          tunValue is Map<String, dynamic> ? tunValue : <String, dynamic>{};
      tun['enable'] = false;
      tun['auto-route'] = false;
      tun['auto-detect-interface'] = false;
      config['tun'] = tun;
    }
    final host = controllerUri.host == '::1' ? '[::1]' : controllerUri.host;
    config['allow-lan'] = false;
    config['bind-address'] = '127.0.0.1';
    config['external-controller'] = '$host:${controllerUri.port}';
    config['secret'] = await controller.ensureSecret();
    await configFile.writeAsString(jsonEncode(config), flush: true);

    final directory = File(configPath).parent.path;
    final process = await Process.start(
        binary, <String>['-d', directory, '-f', configPath],
        mode: ProcessStartMode.normal);
    _process = process;
    _stdout = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_writeLog);
    _stderr = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _writeLog('[stderr] $line'));
    unawaited(process.exitCode.then((code) {
      if (identical(_process, process)) {
        _process = null;
        if (Platform.isWindows) unawaited(_windowsSystemProxy.restoreIfOwned());
        if (!_exits.isClosed) _exits.add(code);
      }
      _writeLog('Mihomo завершился с кодом $code.');
    }));

    Object? lastError;
    for (var attempt = 0; attempt < 12; attempt++) {
      if (!identical(_process, process)) {
        throw StateError(
            'Mihomo завершился при запуске. Проверьте права и логи.${_logTail()}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      try {
        await controller.version();
        _writeLog('Mihomo controller готов.');
        if (Platform.isWindows) {
          await _windowsSystemProxy.enable();
          _writeLog('Системный прокси Windows направлен на 127.0.0.1:7890.');
        }
        return;
      } catch (error) {
        lastError = error;
      }
    }
    await stop();
    throw StateError(
        'External Controller не стал доступен за 12 секунд: $lastError${_logTail()}');
  }

  Future<void> stop() async {
    if (Platform.isWindows) await _windowsSystemProxy.restoreIfOwned();
    final process = _process;
    if (process == null) return;
    _process = null;
    await _stdout?.cancel();
    await _stderr?.cancel();
    _stdout = null;
    _stderr = null;
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      _writeLog('Не дождались завершения процесса Mihomo.');
    }
    _writeLog('Mihomo остановлен.');
  }

  Future<void> dispose() async {
    await stop();
    await _exits.close();
    await _logs.close();
  }
}
