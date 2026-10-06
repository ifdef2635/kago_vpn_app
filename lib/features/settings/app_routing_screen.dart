import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/kago_theme.dart';

/// Russian services that often refuse to work through a VPN (they detect it,
/// or work only with a Russian IP). Offered as a one-tap preset; only the
/// installed ones are added.
const russianServicePackages = <String>{
  'ru.yandex.music',
  'ru.yandex.searchplugin',
  'com.yandex.browser',
  'ru.yandex.yandexmaps',
  'ru.yandex.yandexnavi',
  'ru.yandex.taxi',
  'ru.yandex.disk',
  'ru.yandex.mail',
  'ru.kinopoisk',
  'com.yandex.bank',
  'com.vkontakte.android',
  'com.vk.vkvideo',
  'com.vk.im',
  'ru.ok.android',
  'ru.mail.mailapp',
  'ru.rutube.app',
  'ru.sberbankmobile',
  'ru.vtb24.mobilebanking.android',
  'com.idamob.tinkoff.android',
  'ru.alfabank.mobile.android',
  'ru.raiffeisennews',
  'ru.rostel',
  'ru.ozon.app.android',
  'com.wildberries.ru',
  'com.avito.android',
  'ru.mts.mymts',
  'ru.beeline.services',
  'ru.megafon.mlk',
  'ru.tele2.mytele2',
};

class _App {
  const _App(this.package, this.label);
  final String package;
  final String label;
}

/// Split tunneling: choose apps that bypass the VPN (or the only apps that use
/// it). Saved on the Android side and applied when the VPN starts.
class AppRoutingScreen extends StatefulWidget {
  const AppRoutingScreen({super.key});

  @override
  State<AppRoutingScreen> createState() => _AppRoutingScreenState();
}

class _AppRoutingScreenState extends State<AppRoutingScreen> {
  static const _channel = MethodChannel('net.usekago.app/service');
  List<_App>? _apps;
  String _mode = 'off';
  final _selected = <String>{};
  String _query = '';
  String? _error;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final routing =
          await _channel.invokeMapMethod<String, dynamic>('getAppRouting');
      final raw = await _channel.invokeListMethod<dynamic>('installedApps');
      if (!mounted) return;
      setState(() {
        _mode = routing?['mode'] as String? ?? 'off';
        _selected
          ..clear()
          ..addAll((routing?['packages'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<String>());
        _apps = <_App>[
          for (final item in raw ?? const <dynamic>[])
            if (item is Map) _App('${item['package']}', '${item['label']}'),
        ];
      });
    } on MissingPluginException {
      if (mounted) {
        setState(() => _error =
            tr('Раздельное туннелирование доступно только на Android.'));
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? '$error');
    }
  }

  Future<void> _save() async {
    try {
      await _channel.invokeMethod<bool>('setAppRouting', <String, Object>{
        'mode': _mode,
        'packages': _selected.toList(),
      });
      _dirty = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr(
                'Сохранено. Изменения применятся при следующем подключении VPN.'))));
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message ?? '$error')));
      }
    }
  }

  void _addRussianServices() {
    final installed = _apps
            ?.map((app) => app.package)
            .where(russianServicePackages.contains)
            .toList() ??
        const <String>[];
    setState(() {
      _selected.addAll(installed);
      if (_mode == 'off') _mode = 'exclude';
      _dirty = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(installed.isEmpty
            ? tr('Российские сервисы из списка не установлены.')
            : tr('Добавлено приложений: {n}',
                <String, Object?>{'n': installed.length}))));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    final apps = _apps;
    final query = _query.toLowerCase();
    final visible = apps == null
        ? const <_App>[]
        : (apps
            .where((app) =>
                query.isEmpty ||
                app.label.toLowerCase().contains(query) ||
                app.package.contains(query))
            .toList()
          // Chosen apps first, so the current choice is easy to review.
          ..sort((a, b) {
            final byChoice = (_selected.contains(b.package) ? 1 : 0) -
                (_selected.contains(a.package) ? 1 : 0);
            return byChoice != 0
                ? byChoice
                : a.label.toLowerCase().compareTo(b.label.toLowerCase());
          }));
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _save();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Приложения и VPN')),
          actions: <Widget>[
            TextButton(
                onPressed: _dirty ? _save : null, child: Text(tr('Сохранить'))),
          ],
        ),
        body: _error != null
            ? Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center)))
            : apps == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: visible.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            SegmentedButton<String>(
                              showSelectedIcon: false,
                              segments: <ButtonSegment<String>>[
                                ButtonSegment(
                                    value: 'off', label: Text(tr('Все'))),
                                ButtonSegment(
                                    value: 'exclude',
                                    label: Text(tr('Кроме выбранных'))),
                                ButtonSegment(
                                    value: 'include',
                                    label: Text(tr('Только выбранные'))),
                              ],
                              selected: <String>{_mode},
                              onSelectionChanged: (value) => setState(() {
                                _mode = value.first;
                                _dirty = true;
                              }),
                            ),
                            const SizedBox(height: 10),
                            Text(
                                switch (_mode) {
                                  'exclude' => tr(
                                      'Отмеченные приложения работают напрямую, без VPN. Так работают сервисы, которые не открываются через VPN (Яндекс Музыка, VK, банки).'),
                                  'include' => tr(
                                      'Через VPN идут только отмеченные приложения, остальные — напрямую.'),
                                  _ => tr('Все приложения работают через VPN.'),
                                },
                                style: TextStyle(color: p.muted, fontSize: 13)),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                                onPressed: _addRussianServices,
                                icon: const Icon(Icons.playlist_add_rounded),
                                label:
                                    Text(tr('Российские сервисы — мимо VPN'))),
                            const SizedBox(height: 12),
                            TextField(
                              onChanged: (value) =>
                                  setState(() => _query = value.trim()),
                              decoration: InputDecoration(
                                  isDense: true,
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  hintText: tr('Поиск приложения')),
                            ),
                            const SizedBox(height: 8),
                          ],
                        );
                      }
                      final app = visible[index - 1];
                      final checked = _selected.contains(app.package);
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: checked,
                        enabled: _mode != 'off',
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            _selected.add(app.package);
                          } else {
                            _selected.remove(app.package);
                          }
                          _dirty = true;
                        }),
                        secondary: CircleAvatar(
                          backgroundColor: p.accentSoft,
                          foregroundColor: p.accent,
                          child: Text(app.label.isEmpty
                              ? '?'
                              : app.label.characters.first.toUpperCase()),
                        ),
                        title: Text(app.label,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(app.package,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: p.muted)),
                      );
                    },
                  ),
      ),
    );
  }
}
