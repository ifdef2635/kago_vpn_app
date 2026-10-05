import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as web;

import '../../core/l10n/l10n.dart';
import '../../core/theme/kago_theme.dart';
import 'kago_api.dart';

/// What the in-app usekago.net page is opened for.
enum SiteSessionMode {
  /// /login: sign in with Telegram (the site's Telegram OIDC button). The
  /// screen closes by itself once the site lands on /my.
  login,

  /// /my with the app's session: link Telegram and other site-only actions.
  cabinet,
}

/// usekago.net inside the app (Android WebView / Windows WebView2).
///
/// Telegram sign-in on the site runs Telegram's OIDC library, which opens
/// oauth.telegram.org in a popup and hands the `id_token` back to the page;
/// the site then exchanges it for its httpOnly session cookies. A plain
/// HTTP client cannot do that, so the app shows the real page (popups
/// included) and afterwards copies the session cookies into [KagoCookieStore].
/// Pops with `true` when a session was taken over.
class SiteSessionScreen extends StatefulWidget {
  const SiteSessionScreen({super.key, required this.mode, required this.api});
  final SiteSessionMode mode;
  final KagoApi api;

  static Future<bool> open(BuildContext context, SiteSessionMode mode,
      {required KagoApi api}) async {
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => SiteSessionScreen(mode: mode, api: api)));
    return result ?? false;
  }

  /// Forgets the site session inside the WebView too (app logout).
  static Future<void> clearWebSession() async {
    try {
      final cookies = web.CookieManager.instance();
      for (final url in _cookieUrls) {
        await cookies.deleteCookies(url: web.WebUri(url));
      }
    } catch (_) {
      // No WebView on this platform or nothing stored.
    }
  }

  // The refresh cookie may be scoped to the API path, so ask for each.
  static const _cookieUrls = <String>[
    kagoSiteUrl,
    '$kagoApiBase/',
    '$kagoApiBase/auth/refresh',
  ];

  @override
  State<SiteSessionScreen> createState() => _SiteSessionScreenState();
}

class _SiteSessionScreenState extends State<SiteSessionScreen> {
  final _cookies = web.CookieManager.instance();
  double _progress = 0;
  bool _ready = false;
  bool _finishing = false;
  bool _autoClicked = false;
  String? _error;

  String get _startUrl => widget.mode == SiteSessionMode.login
      ? '$kagoSiteUrl/login?next=%2Fmy'
      : '$kagoSiteUrl/my';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  /// In cabinet mode the page must see the app's session.
  Future<void> _prepare() async {
    if (widget.mode == SiteSessionMode.cabinet) {
      try {
        final current = await widget.api.cookies.all();
        for (final entry in current.entries) {
          await _cookies.setCookie(
            url: web.WebUri(kagoSiteUrl),
            name: entry.key,
            value: entry.value,
            isSecure: true,
            isHttpOnly: true,
          );
        }
      } catch (_) {
        // The page then simply asks to sign in.
      }
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<Map<String, String>> _readSiteCookies() async {
    final found = <String, String>{};
    for (final url in SiteSessionScreen._cookieUrls) {
      for (final cookie in await _cookies.getCookies(url: web.WebUri(url))) {
        final value = '${cookie.value ?? ''}';
        if (cookie.name.isNotEmpty && value.isNotEmpty) {
          found[cookie.name] = value;
        }
      }
    }
    return found;
  }

  /// Takes the site's session into the app and checks it with /auth/me.
  Future<void> _takeOverSession() async {
    if (_finishing) return;
    _finishing = true;
    try {
      final cookies = await _readSiteCookies();
      if (cookies.isEmpty) throw StateError('no cookies');
      await widget.api.cookies.replaceAll(cookies);
      await widget.api.me();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      _finishing = false;
      if (mounted) {
        setState(() => _error = tr(
            'Не удалось перенести вход в приложение. Попробуйте ещё раз или войдите по email и паролю.'));
      }
    }
  }

  void _onUrl(web.WebUri? url) {
    if (url == null) return;
    final onCabinet = url.host.endsWith('usekago.net') &&
        (url.path == '/my' || url.path.startsWith('/my/'));
    if (widget.mode == SiteSessionMode.login && onCabinet) {
      unawaited(_takeOverSession());
    }
  }

  /// Saves a tap: press the site's "Войти через Telegram" once the page is up.
  Future<void> _autoStartTelegram(
      web.InAppWebViewController controller, web.WebUri? url) async {
    if (widget.mode != SiteSessionMode.login || _autoClicked) return;
    if (url == null || url.path != '/login') return;
    _autoClicked = true;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    try {
      await controller.evaluateJavascript(
          source: "document.querySelector('.tg-login-btn')?.click();");
    } catch (_) {
      // The user can still press the button.
    }
  }

  Future<void> _showPopup(web.CreateWindowAction action) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 520,
          height: 640,
          child: Column(children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                  tooltip: tr('Закрыть'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close_rounded)),
            ),
            Expanded(
              child: web.InAppWebView(
                windowId: action.windowId,
                initialSettings: _settings,
                onCloseWindow: (_) {
                  if (Navigator.of(dialogContext).canPop()) {
                    Navigator.of(dialogContext).pop();
                  }
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  web.InAppWebViewSettings get _settings => web.InAppWebViewSettings(
        javaScriptEnabled: true,
        // Telegram's login opens oauth.telegram.org with window.open.
        supportMultipleWindows: true,
        javaScriptCanOpenWindowsAutomatically: true,
        thirdPartyCookiesEnabled: true,
        transparentBackground: false,
      );

  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    final login = widget.mode == SiteSessionMode.login;
    return Scaffold(
      appBar: AppBar(
        title: Text(login ? tr('Вход через Telegram') : tr('Кабинет на сайте')),
        actions: <Widget>[
          if (!login)
            TextButton(
                onPressed: () async {
                  // Keep a session the site may have refreshed meanwhile.
                  try {
                    final cookies = await _readSiteCookies();
                    if (cookies.isNotEmpty) {
                      await widget.api.cookies.replaceAll(cookies);
                    }
                  } catch (_) {}
                  if (context.mounted) Navigator.of(context).pop(true);
                },
                child: Text(tr('Готово'))),
        ],
        bottom: _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                    minHeight: 2, value: _progress == 0 ? null : _progress))
            : null,
      ),
      body: Column(children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          color:
              _error == null ? p.accentSoft : p.danger.withValues(alpha: .12),
          child: Text(
              _error ??
                  (login
                      ? tr(
                          'Нажмите «Войти через Telegram» и подтвердите вход в Telegram. Окно закроется само.')
                      : tr(
                          'Здесь можно привязать Telegram к аккаунту. Нажмите «Готово», когда закончите.')),
              style: TextStyle(
                  fontSize: 13, color: _error == null ? p.text : p.danger)),
        ),
        Expanded(
          child: !_ready
              ? const Center(child: CircularProgressIndicator())
              : web.InAppWebView(
                  initialUrlRequest: web.URLRequest(url: web.WebUri(_startUrl)),
                  initialSettings: _settings,
                  onProgressChanged: (_, progress) =>
                      setState(() => _progress = progress / 100),
                  onUpdateVisitedHistory: (_, url, __) => _onUrl(url),
                  onLoadStop: (controller, url) {
                    _onUrl(url);
                    unawaited(_autoStartTelegram(controller, url));
                  },
                  onCreateWindow: (_, action) async {
                    unawaited(_showPopup(action));
                    return true;
                  },
                ),
        ),
      ]),
    );
  }
}
