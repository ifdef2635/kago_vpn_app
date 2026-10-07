import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/models/mihomo_models.dart';
import '../../core/network/app_providers.dart';
import '../../core/update/app_updater.dart';

/// The newer release on GitHub, or null when this version is the latest.
/// Checked a few seconds after start and then every 6 hours.
final appUpdateProvider = FutureProvider<AppRelease?>((ref) async {
  if (!AppUpdater.supported) return null;
  final timer = Timer(const Duration(hours: 6), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  await Future<void>.delayed(const Duration(seconds: 3));
  final viaCore = !Platform.isAndroid && ref.read(desktopCoreRunningProvider);
  return AppUpdater(proxyPort: viaCore ? 7890 : null).check();
});

/// Offers each new version once per app run as soon as the check finds it.
class UpdatePrompt extends ConsumerStatefulWidget {
  const UpdatePrompt({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends ConsumerState<UpdatePrompt> {
  String? _offered;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AppRelease?>>(appUpdateProvider, (_, next) {
      final release = next.valueOrNull;
      if (release == null || release.version == _offered) return;
      _offered = release.version;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showUpdateDialog(context, release);
      });
    });
    return widget.child;
  }
}

Future<void> showUpdateDialog(BuildContext context, AppRelease release) =>
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UpdateDialog(release: release));

enum _Stage { offer, downloading, installing, permission, manual, failed }

class _UpdateDialog extends ConsumerStatefulWidget {
  const _UpdateDialog({required this.release});
  final AppRelease release;

  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<_UpdateDialog> {
  _Stage _stage = _Stage.offer;
  int _received = 0;
  int _total = 0;
  String _error = '';
  File? _file;
  CancelToken? _cancel;

  AppUpdater get _updater => AppUpdater(
      proxyPort: !Platform.isAndroid && ref.read(desktopCoreRunningProvider)
          ? 7890
          : null);

  Future<void> _download() async {
    final cancel = CancelToken();
    setState(() {
      _stage = _Stage.downloading;
      _received = 0;
      _total = 0;
      _cancel = cancel;
    });
    try {
      final file = await _updater.download(widget.release, cancelToken: cancel,
          onProgress: (received, total) {
        if (mounted) {
          setState(() {
            _received = received;
            _total = total;
          });
        }
      });
      _file = file;
      await _install();
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        if (mounted) setState(() => _stage = _Stage.offer);
        return;
      }
      _fail(error.message ?? '$error');
    } catch (error) {
      _fail('$error');
    }
  }

  Future<void> _install() async {
    final file = _file;
    if (file == null) return _download();
    setState(() => _stage = _Stage.installing);
    try {
      // Desktop: stop the core first so the system proxy is restored before
      // the installer replaces the app and this process quits.
      if (!Platform.isAndroid) {
        await ref
            .read(mihomoProcessProvider)
            .stop()
            .timeout(const Duration(seconds: 6))
            .catchError((Object _) {});
        ref.read(desktopCoreRunningProvider.notifier).state = false;
      }
      final result = await _updater.install(file);
      if (!mounted) return;
      switch (result) {
        case UpdateInstallResult.started:
          if (Platform.isAndroid) {
            Navigator.of(context).pop();
          } else if (Platform.isWindows) {
            // Quit at once, so the installer finds no file in use. A normal
            // exit can hang in plugin shutdown (WebView2); the core and the
            // system proxy are already stopped above.
            Process.killPid(pid, ProcessSignal.sigkill);
            exit(0);
          } else {
            exit(0);
          }
        case UpdateInstallResult.needsPermission:
          setState(() => _stage = _Stage.permission);
        case UpdateInstallResult.openedManually:
          setState(() => _stage = _Stage.manual);
      }
    } catch (error) {
      _fail('$error');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.failed;
      _error = message;
    });
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    return AlertDialog(
      icon: const Icon(Icons.system_update_rounded),
      title: Text(tr('Доступна версия {version}',
          <String, Object?>{'version': release.version})),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 280),
        child: SingleChildScrollView(child: _body(context)),
      ),
      actions: _actions(context),
    );
  }

  Widget _body(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    switch (_stage) {
      case _Stage.offer:
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(tr(
                  'Обновление скачается и установится прямо из приложения. Настройки и вход сохранятся.')),
              if (widget.release.notes.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(widget.release.notes,
                    style: TextStyle(color: muted, fontSize: 13)),
              ],
            ]);
      case _Stage.downloading:
        final progress = _total > 0 ? _received / _total : null;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 10),
              Text(
                  _total > 0
                      ? tr('Скачано {done} из {total}', <String, Object?>{
                          'done': formatBytes(_received),
                          'total': formatBytes(_total),
                        })
                      : tr('Скачивание…'),
                  style: TextStyle(color: muted, fontSize: 13)),
            ]);
      case _Stage.installing:
        return Row(children: <Widget>[
          const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 14),
          Expanded(
              child: Text(Platform.isAndroid
                  ? tr('Открывается установка…')
                  : tr('Устанавливается. KaGo VPN перезапустится сам.'))),
        ]);
      case _Stage.permission:
        return Text(tr(
            'Разрешите KaGo VPN устанавливать приложения (откроются настройки), вернитесь и нажмите «Установить».'));
      case _Stage.manual:
        return Text(tr(
            'Открыт образ диска с новой версией: перетащите KaGo VPN в «Программы» с заменой и запустите снова.'));
      case _Stage.failed:
        return Text(tr('Не удалось обновить: {error}',
            <String, Object?>{'error': _error}));
    }
  }

  List<Widget> _actions(BuildContext context) {
    void close() => Navigator.of(context).pop();
    switch (_stage) {
      case _Stage.offer:
        return <Widget>[
          TextButton(onPressed: close, child: Text(tr('Позже'))),
          FilledButton(onPressed: _download, child: Text(tr('Обновить'))),
        ];
      case _Stage.downloading:
        return <Widget>[
          TextButton(
              onPressed: () => _cancel?.cancel(), child: Text(tr('Отмена'))),
        ];
      case _Stage.installing:
        return const <Widget>[];
      case _Stage.permission:
        return <Widget>[
          TextButton(onPressed: close, child: Text(tr('Позже'))),
          FilledButton(onPressed: _install, child: Text(tr('Установить'))),
        ];
      case _Stage.manual:
        return <Widget>[
          FilledButton(onPressed: close, child: Text(tr('Понятно'))),
        ];
      case _Stage.failed:
        return <Widget>[
          TextButton(onPressed: close, child: Text(tr('Позже'))),
          FilledButton(onPressed: _download, child: Text(tr('Повторить'))),
        ];
    }
  }
}
