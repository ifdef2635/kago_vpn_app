import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/subscriptions/config_builder.dart';
import '../../features/subscriptions/russian_rules.dart';
import 'mihomo_controller.dart';
import 'mihomo_macos.dart';
import 'mihomo_windows_core_updater.dart';
import 'mihomo_windows_system_proxy.dart';
import '../l10n/l10n.dart';

/// Desktop lifecycle: the managed Windows core, the core bundled in the macOS
/// app, or (Linux) a user-supplied executable.
class MihomoProcessManager {
  MihomoProcessManager({
    MihomoWindowsCoreUpdater? coreUpdater,
    MihomoWindowsSystemProxy? windowsSystemProxy,
    MihomoMacosSystemProxy? macosSystemProxy,
  })  : _coreUpdater = coreUpdater ?? MihomoWindowsCoreUpdater(),
        _windowsSystemProxy = windowsSystemProxy ?? MihomoWindowsSystemProxy(),
        _macosSystemProxy = macosSystemProxy ?? MihomoMacosSystemProxy();

  static const _binaryKey = 'mihomo.binary';
  final MihomoWindowsCoreUpdater _coreUpdater;
  final MihomoWindowsSystemProxy _windowsSystemProxy;
  final MihomoMacosSystemProxy _macosSystemProxy;

  /// Windows and macOS have a built-in core and route apps through the
  /// system proxy; Linux uses a manual core path.
  static bool get _managedDesktop => Platform.isWindows || Platform.isMacOS;

  Future<void> _enableSystemProxy(
      {bool tun = false, bool routesRussia = false}) async {
    if (Platform.isWindows) {
      await _windowsSystemProxy.enable(subscriptionRoutesRussia: routesRussia);
    }
    if (Platform.isMacOS) {
      await _macosSystemProxy.enable(
          tun: tun, subscriptionRoutesRussia: routesRussia);
    }
  }

  Future<void> _restoreSystemProxy() async {
    if (Platform.isWindows) await _windowsSystemProxy.restoreIfOwned();
    if (Platform.isMacOS) await _macosSystemProxy.restoreIfOwned();
  }

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
    return tr('\nЛог ядра:\n{v}', <String, Object?>{'v': tail.join('\n')});
  }

  /// Manual core path. Only Linux uses it (it has no built-in core); on
  /// Windows and macOS the core is always the managed one, so a path saved by
  /// an older version is dropped instead of silently overriding it.
  Future<String?> get executable async {
    final prefs = await SharedPreferences.getInstance();
    if (_managedDesktop) {
      if (prefs.containsKey(_binaryKey)) await prefs.remove(_binaryKey);
      return null;
    }
    return prefs.getString(_binaryKey);
  }

  Future<void> saveExecutable(String path) async {
    if (_managedDesktop) return;
    final value = path.trim();
    final prefs = await SharedPreferences.getInstance();
    if (value.isEmpty) {
      await prefs.remove(_binaryKey);
    } else {
      await prefs.setString(_binaryKey, value);
    }
  }

  Future<MihomoCoreInstall?> installedCore() =>
      Platform.isMacOS ? MihomoMacosCore.installed() : _coreUpdater.installed();

  /// Downloads or updates the managed Windows core in the background so it is
  /// ready before the first connection. Failures are logged, never thrown.
  Future<void> prepareCore() async {
    if (!Platform.isWindows) return;
    try {
      final core = await _coreUpdater.ensureInstalled(onLog: _writeLog);
      _writeLog(tr('Встроенный Mihomo {version} готов.',
          <String, Object?>{'version': core.version}));
    } catch (error) {
      _writeLog(tr('Автозагрузка ядра не удалась: {error}',
          <String, Object?>{'error': error}));
    }
  }

  Future<void> recoverStaleSystemProxy() async {
    try {
      await _restoreSystemProxy();
    } catch (error) {
      _writeLog(tr(
          'Не удалось восстановить сохранённые proxy settings: {error}',
          <String, Object?>{'error': error}));
    }
  }

  Future<MihomoCoreInstall> updateCore() async {
    if (_process != null) {
      throw StateError(
          tr('Остановите Mihomo перед проверкой/установкой обновления.'));
    }
    return _coreUpdater.ensureInstalled(forceCheck: true, onLog: _writeLog);
  }

  Future<void> start({required String configPath}) async {
    if (_process != null) return;
    final overridePath = (await executable)?.trim() ?? '';
    final usingOverride = overridePath.isNotEmpty;
    final String binary;
    var tunMode = false;
    if (usingOverride) {
      binary = overridePath;
    } else if (Platform.isWindows) {
      final core = await _coreUpdater.ensureInstalled(onLog: _writeLog);
      binary = core.executable.path;
      _writeLog(tr('Запускается встроенный Mihomo {version}.',
          <String, Object?>{'version': core.version}));
    } else if (Platform.isMacOS) {
      await MihomoMacosCore.killStale();
      final core = await MihomoMacosCore.resolve(_writeLog);
      binary = core.binary.path;
      tunMode = core.tun;
      _writeLog(tr('Запускается встроенный Mihomo {version}.',
          <String, Object?>{'version': MihomoPinnedCore.version}));
    } else {
      throw StateError(
          tr('Для этой desktop-платформы укажите путь к Mihomo в настройках.'));
    }
    if (!await File(binary).exists()) {
      throw FileSystemException(
          usingOverride
              ? tr(
                  'Файл Mihomo из настроек не найден. Исправьте путь или очистите поле, чтобы использовать встроенное ядро')
              : tr(
                  'Встроенный Mihomo не найден на диске. Нажмите «Проверить и установить обновление» в настройках'),
          binary);
    }
    if (!await File(configPath).exists()) {
      throw FileSystemException(
          tr('Сначала импортируйте YAML-подписку'), configPath);
    }

    final controller = MihomoController(
      connectTimeout: const Duration(milliseconds: 500),
      receiveTimeout: const Duration(seconds: 1),
    );
    final controllerUri = Uri.parse(await controller.endpoint);
    if (controllerUri.scheme != 'http' ||
        !<String>['127.0.0.1', 'localhost', '::1']
            .contains(controllerUri.host)) {
      throw StateError(tr(
          'Desktop core запускается с локальным HTTP controller. Укажите http://127.0.0.1:<port>.'));
    }
    final configFile = File(configPath);
    final Object? decoded = jsonDecode(await configFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw FormatException(tr('Активная конфигурация Mihomo повреждена.'));
    }
    final config = decoded;
    final routesRussia = RussianRules.present(config);
    if (_managedDesktop) {
      config['mixed-port'] = 7890;
      final tunValue = config['tun'];
      final tun =
          tunValue is Map<String, dynamic> ? tunValue : <String, dynamic>{};
      if (tunMode) {
        // macOS "all traffic" mode: the root core creates a utun and routes
        // every app through it (Telegram ignores the system proxy).
        tun['enable'] = true;
        tun.putIfAbsent('stack', () => 'mixed');
        tun['auto-route'] = true;
        tun['auto-detect-interface'] = true;
        tun['dns-hijack'] = const <String>['any:53'];
        MihomoConfigBuilder.ensureDns(config);
      } else {
        tun['enable'] = false;
        tun['auto-route'] = false;
        tun['auto-detect-interface'] = false;
      }
      config['tun'] = tun;
    }
    final host = controllerUri.host == '::1' ? '[::1]' : controllerUri.host;
    // The file on disk is re-read here: apply the same lock-down as on import.
    MihomoConfigBuilder.lockToLoopback(config);
    config['external-controller'] = '$host:${controllerUri.port}';
    config['secret'] = await controller.ensureSecret();
    await configFile.writeAsString(jsonEncode(config), flush: true);

    final directory = File(configPath).parent.path;
    // The macOS TUN wrapper takes no arguments: it runs the root core with its
    // own root-owned home and reads the config from stdin.
    final process = await Process.start(
        binary,
        tunMode
            ? const <String>[]
            : <String>['-d', directory, '-f', configPath],
        mode: ProcessStartMode.normal);
    if (tunMode) {
      process.stdin.add(utf8.encode(jsonEncode(config)));
      await process.stdin.flush();
      await process.stdin.close();
    }
    _process = process;
    if (Platform.isMacOS) unawaited(MihomoMacosCore.rememberPid(process.pid));
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
        if (Platform.isMacOS) unawaited(MihomoMacosCore.rememberPid(null));
        unawaited(_restoreSystemProxy());
        if (!_exits.isClosed) _exits.add(code);
      }
      _writeLog(tr('Mihomo завершился с кодом {code}.',
          <String, Object?>{'code': code}));
    }));

    Object? lastError;
    for (var attempt = 0; attempt < 12; attempt++) {
      if (!identical(_process, process)) {
        throw StateError(tr(
            'Mihomo завершился при запуске. Проверьте права и логи.{v}',
            <String, Object?>{'v': _logTail()}));
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      try {
        await controller.version();
        _writeLog(tr('Mihomo controller готов.'));
        if (_managedDesktop) {
          await _enableSystemProxy(tun: tunMode, routesRussia: routesRussia);
          _writeLog(tr('Системный прокси направлен на 127.0.0.1:7890.'));
          if (tunMode) _writeLog(tr('Весь трафик идёт через VPN (TUN).'));
        }
        return;
      } catch (error) {
        lastError = error;
      }
    }
    await stop();
    throw StateError(tr(
        'External Controller не стал доступен за 12 секунд: {lastError}{v}',
        <String, Object?>{'lastError': lastError, 'v': _logTail()}));
  }

  Future<void> stop() async {
    await _restoreSystemProxy();
    final process = _process;
    if (process == null) return;
    _process = null;
    await _stdout?.cancel();
    await _stderr?.cancel();
    _stdout = null;
    _stderr = null;
    process.kill();
    if (Platform.isMacOS) unawaited(MihomoMacosCore.rememberPid(null));
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      _writeLog(tr('Не дождались завершения процесса Mihomo.'));
    }
    _writeLog(tr('Mihomo остановлен.'));
  }

  Future<void> dispose() async {
    await stop();
    await _exits.close();
    await _logs.close();
  }
}
