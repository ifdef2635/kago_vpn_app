import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as web;
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_widgets.dart';
import '../../core/theme/kago_theme.dart';
import 'kago_api.dart';
import 'site_navigation_policy.dart';

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
/// oauth.telegram.org in a popup and hands the `id_token` back to the page.
/// A plain HTTP client cannot get that token, so the app shows the real page
/// (popups included). In login mode the page's `POST /auth/telegram` is
/// handed to the app, which makes the call itself and so gets its own
/// session, just like the email login. Copying the WebView's cookies is only
/// the fallback. Pops with `true` when the app has a session.
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

const _telegramHandler = 'kagoTelegramLogin';

/// Telegram's brand blue (also used on usekago.net).
const telegramBlue = Color(0xFF229ED9);

/// Presses the site's Telegram button; `false` when the page has none.
const _pressTelegram = '''
(function () {
  var button = document.querySelector('.tg-login-btn');
  if (!button) return false;
  button.click();
  return true;
})();
''';

/// Runs before the site's own scripts: the page's `fetch` to /auth/telegram
/// goes to the app instead of the network, and the app's answer becomes the
/// page's response (so an error shows up on the site as usual).
const _telegramHook = '''
(function () {
  if (window.__kagoTelegramHook) return;
  window.__kagoTelegramHook = true;
  var original = window.fetch;
  window.fetch = function (input, init) {
    try {
      var url = typeof input === 'string' ? input : (input && input.url) || '';
      var path = new URL(url, location.href).pathname;
      var bridge = window.flutter_inappwebview;
      if (path === '/api/v1/public/auth/telegram' && init && init.body &&
          bridge && bridge.callHandler) {
        return bridge.callHandler('$_telegramHandler', String(init.body))
          .then(function (answer) {
            answer = answer || {};
            return new Response(answer.body || '{}', {
              status: answer.status || 500,
              headers: { 'Content-Type': 'application/json' }
            });
          });
      }
    } catch (e) {}
    return original.apply(this, arguments);
  };
})();
''';

class _SiteSessionScreenState extends State<SiteSessionScreen> {
  final _cookies = web.CookieManager.instance();
  web.InAppWebViewController? _page;

  /// Telegram's login window (window.open from the page), shown full screen.
  web.CreateWindowAction? _popup;
  double _popupProgress = 0;

  double _progress = 0;
  bool _ready = false;
  bool _pageLoaded = false;
  bool _finishing = false;
  bool _autoStarted = false;

  /// Login mode shows a KAGO screen instead of the site; the site itself is
  /// shown only if its Telegram button cannot be found.
  bool _showSite = false;
  String? _error;

  bool get _login => widget.mode == SiteSessionMode.login;

  String get _startUrl =>
      _login ? '$kagoSiteUrl/login?next=%2Fmy' : '$kagoSiteUrl/my';

  @override
  void initState() {
    super.initState();
    _showSite = !_login;
    _prepare();
  }

  /// In cabinet mode the page must see the app's session.
  Future<void> _prepare() async {
    if (!_login) {
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

  void _fail(String message) {
    _finishing = false;
    if (mounted) setState(() => _error = message);
  }

  static String get _transferFailed => tr(
      'Не удалось перенести вход в приложение. Попробуйте ещё раз или войдите по email и паролю.');

  /// The page's `POST /auth/telegram` body, done by the app's own client.
  /// Returns what the page's `fetch` should resolve with.
  Future<Map<String, Object?>> _telegramFromPage(
      web.JavaScriptHandlerFunctionData data) async {
    // Only the site's own top-level page may hand over a token: not another
    // domain ending in "usekago.net", not an iframe, not plain HTTP.
    if (!data.isMainFrame ||
        !SiteNavigationPolicy.isKagoOrigin(data.origin) ||
        _finishing) {
      return <String, Object?>{'status': 409, 'body': '{}'};
    }
    _finishing = true;
    if (mounted) {
      setState(() {
        _popup = null;
        _error = null;
      });
    }
    try {
      final body = jsonDecode('${data.args.isEmpty ? '' : data.args.first}');
      final token = body is Map<String, dynamic> ? body['id_token'] : null;
      if (token is! String || token.isEmpty) throw const FormatException();
      await widget.api.telegramLogin(token);
      await widget.api.me();
      if (mounted) Navigator.of(context).pop(true);
      return <String, Object?>{'status': 200, 'body': '{}'};
    } catch (error) {
      final message =
          error is KagoApiException ? error.message : _transferFailed;
      _fail(message);
      return <String, Object?>{
        'status': error is KagoApiException ? (error.status ?? 400) : 400,
        'body': jsonEncode(<String, String>{'detail': message}),
      };
    }
  }

  /// Fallback: takes the site's session cookies into the app and checks them
  /// with /auth/me. The WebView may store the cookies a moment after the
  /// page has moved on, so this tries a few times.
  Future<void> _takeOverSession() async {
    if (_finishing) return;
    _finishing = true;
    if (mounted) setState(() => _error = null);
    for (final delay in const <int>[300, 1000, 2500]) {
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (!mounted) return;
      try {
        final cookies = await _readSiteCookies();
        if (cookies.isEmpty) continue;
        await widget.api.cookies.replaceAll(cookies);
        await widget.api.me();
        if (mounted) Navigator.of(context).pop(true);
        return;
      } catch (_) {
        // Try again with whatever the WebView holds by then.
      }
    }
    _fail(_transferFailed);
  }

  void _onUrl(web.WebUri? url) {
    if (url == null) return;
    final onCabinet = SiteNavigationPolicy.isKagoOrigin(url) &&
        (url.path == '/my' || url.path.startsWith('/my/'));
    if (_login && onCabinet) unawaited(_takeOverSession());
  }

  /// Opens Telegram's login window through the site's own button.
  Future<void> _startTelegram() async {
    final page = _page;
    if (page == null || _finishing) return;
    setState(() => _error = null);
    try {
      final pressed = await page.evaluateJavascript(source: _pressTelegram);
      // The site changed: let the user use the page itself.
      if (pressed == false && mounted) setState(() => _showSite = true);
    } catch (_) {
      if (mounted) setState(() => _showSite = true);
    }
  }

  /// Saves a tap: opens Telegram as soon as the login page is up.
  Future<void> _autoStart(web.WebUri? url) async {
    if (!_login || _autoStarted) return;
    if (url == null || url.path != '/login') return;
    _autoStarted = true;
    // Give the page a moment to wire up its button.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted && _popup == null) await _startTelegram();
  }

  /// "Continue with Telegram" opens tg:// (or an Android intent:// link to
  /// it); a WebView cannot, so hand those to the system.
  /// Applies [SiteNavigationPolicy]: the site and Telegram's login load
  /// here, other HTTPS pages open in the browser, Telegram links in the
  /// Telegram app, anything else is refused.
  Future<web.NavigationActionPolicy> _openExternal(
      web.InAppWebViewController controller,
      web.NavigationAction action) async {
    final url = action.request.url;
    if (url == null) return web.NavigationActionPolicy.CANCEL;
    if (!action.isForMainFrame) {
      return SiteNavigationPolicy.allowSubframe(url)
          ? web.NavigationActionPolicy.ALLOW
          : web.NavigationActionPolicy.CANCEL;
    }
    if (url.scheme.toLowerCase() == 'intent') {
      final link = url.toString();
      final telegram = SiteNavigationPolicy.telegramFromIntent(link);
      if (telegram == null || !await _launch(telegram)) {
        final fallback = SiteNavigationPolicy.intentFallback(link);
        if (fallback != null) {
          if (SiteNavigationPolicy.decide(fallback) == SiteNavigation.allow) {
            await controller.loadUrl(
                urlRequest: web.URLRequest(url: web.WebUri.uri(fallback)));
          } else {
            await _launch(fallback);
          }
        }
      }
      return web.NavigationActionPolicy.CANCEL;
    }
    switch (SiteNavigationPolicy.decide(url)) {
      case SiteNavigation.allow:
        return web.NavigationActionPolicy.ALLOW;
      case SiteNavigation.external:
        await _launch(url);
        return web.NavigationActionPolicy.CANCEL;
      case SiteNavigation.block:
        return web.NavigationActionPolicy.CANCEL;
    }
  }

  static Future<bool> _launch(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  void _closePopup() => setState(() => _popup = null);

  web.InAppWebViewSettings get _settings => web.InAppWebViewSettings(
        javaScriptEnabled: true,
        // No file:// or content:// pages, and the JavaScript bridge only for
        // the top-level page of the site or Telegram's login.
        allowFileAccess: false,
        allowContentAccess: false,
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
        javaScriptHandlersForMainFrameOnly: true,
        javaScriptHandlersOriginAllowList: <String>{
          r'^https://([a-z0-9-]+\.)*usekago\.net$',
          r'^https://([a-z0-9-]+\.)*telegram\.org$',
        },
        // Telegram's login opens oauth.telegram.org with window.open.
        supportMultipleWindows: true,
        javaScriptCanOpenWindowsAutomatically: true,
        thirdPartyCookiesEnabled: true,
        useShouldOverrideUrlLoading: true,
        transparentBackground: false,
      );

  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    final popupOpen = _popup != null;
    final loading =
        popupOpen ? _popupProgress < 1 : (_showSite && _progress < 1);
    return PopScope(
      canPop: !popupOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && popupOpen) _closePopup();
      },
      child: Scaffold(
        backgroundColor: p.canvas,
        appBar: AppBar(
          backgroundColor: p.canvas,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
              tooltip: popupOpen ? tr('Назад') : tr('Закрыть'),
              onPressed: () =>
                  popupOpen ? _closePopup() : Navigator.of(context).maybePop(),
              icon: Icon(
                  popupOpen ? Icons.arrow_back_rounded : Icons.close_rounded)),
          title: Text(
              _login ? tr('Вход через Telegram') : tr('Кабинет на сайте'),
              style: const TextStyle(
                  fontSize: 17, fontWeight: KaGoWeight.extraBold)),
          actions: <Widget>[
            if (!_login && !popupOpen)
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
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: loading
                ? LinearProgressIndicator(
                    minHeight: 2,
                    color: telegramBlue,
                    backgroundColor: Colors.transparent,
                    value: (popupOpen ? _popupProgress : _progress) == 0
                        ? null
                        : (popupOpen ? _popupProgress : _progress))
                : const SizedBox(height: 2),
          ),
        ),
        body: Column(children: <Widget>[
          if (_showSite && (_error != null || !_login))
            _Notice(
                text: _error ??
                    tr('Здесь можно привязать Telegram к аккаунту. Нажмите «Готово», когда закончите.'),
                error: _error != null),
          Expanded(
            child: Stack(children: <Widget>[
              Positioned.fill(
                child: !_ready
                    ? const SizedBox.shrink()
                    : web.InAppWebView(
                        initialUrlRequest:
                            web.URLRequest(url: web.WebUri(_startUrl)),
                        initialSettings: _settings,
                        initialUserScripts: _login
                            ? UnmodifiableListView<
                                web.UserScript>(<web.UserScript>[
                                web.UserScript(
                                    source: _telegramHook,
                                    injectionTime: web.UserScriptInjectionTime
                                        .AT_DOCUMENT_START),
                              ])
                            : null,
                        onWebViewCreated: (controller) {
                          _page = controller;
                          if (!_login) return;
                          controller.addJavaScriptHandler(
                              handlerName: _telegramHandler,
                              callback: _telegramFromPage);
                        },
                        shouldOverrideUrlLoading: _openExternal,
                        onProgressChanged: (_, progress) =>
                            setState(() => _progress = progress / 100),
                        onUpdateVisitedHistory: (_, url, __) => _onUrl(url),
                        onLoadStop: (_, url) {
                          if (!_pageLoaded) setState(() => _pageLoaded = true);
                          _onUrl(url);
                          unawaited(_autoStart(url));
                        },
                        onCreateWindow: (_, action) async {
                          // Popups only for the site and Telegram's login;
                          // the popup applies the same navigation rules.
                          final target = action.request.url;
                          if (target != null && target.toString().isNotEmpty) {
                            final decision =
                                SiteNavigationPolicy.decide(target);
                            if (decision == SiteNavigation.external) {
                              await _launch(target);
                            }
                            if (decision != SiteNavigation.allow) return false;
                          }
                          setState(() {
                            _popup = action;
                            _popupProgress = 0;
                          });
                          return true;
                        },
                      ),
              ),
              if (!_showSite)
                Positioned.fill(
                  child: _TelegramCover(
                    busy: _finishing || !_pageLoaded,
                    status: _finishing
                        ? tr('Входим в аккаунт…')
                        : !_pageLoaded
                            ? tr('Подключаемся к usekago.net…')
                            : null,
                    error: _error,
                    onContinue:
                        _pageLoaded && !_finishing ? _startTelegram : null,
                  ),
                ),
              if (_popup case final popup?)
                Positioned.fill(
                  child: ColoredBox(
                    color: p.canvas,
                    child: web.InAppWebView(
                      key: ValueKey<int>(popup.windowId),
                      windowId: popup.windowId,
                      initialSettings: _settings,
                      shouldOverrideUrlLoading: _openExternal,
                      onProgressChanged: (_, progress) =>
                          setState(() => _popupProgress = progress / 100),
                      onCloseWindow: (_) {
                        if (mounted && _popup == popup) _closePopup();
                      },
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A one-line strip above the site page (hint or error).
class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.error});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: error ? p.danger.withValues(alpha: .12) : p.accentSoft,
      child: Text(text,
          style: TextStyle(fontSize: 13, color: error ? p.danger : p.text)),
    );
  }
}

/// What the user sees in login mode instead of the site: the KAGO and
/// Telegram marks, what is happening, and a "Continue with Telegram" button.
class _TelegramCover extends StatelessWidget {
  const _TelegramCover(
      {required this.busy,
      required this.status,
      required this.error,
      required this.onContinue});
  final bool busy;
  final String? status;
  final String? error;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    return ColoredBox(
      color: p.canvas,
      child: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                const _PairedMarks(),
                const SizedBox(height: 28),
                Text(tr('Вход через Telegram'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: KaGoWeight.heading)),
                const SizedBox(height: 10),
                Text(tr('Подтвердите вход в Telegram — пароль не нужен. Аккаунт KAGO и подписка подключатся автоматически.'),
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 14.5, height: 1.4, color: p.muted)),
                const SizedBox(height: 28),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: busy
                      ? Column(
                          key: const ValueKey<String>('busy'),
                          children: <Widget>[
                              const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.6, color: telegramBlue)),
                              const SizedBox(height: 14),
                              Text(status ?? '',
                                  style: TextStyle(
                                      color: p.muted, fontSize: 13.5)),
                            ])
                      : Column(
                          key: const ValueKey<String>('ready'),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                              if (error != null) ...<Widget>[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: p.danger.withValues(alpha: .1),
                                      borderRadius:
                                          BorderRadius.circular(KaGoRadius.md)),
                                  child: Text(error!,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: p.danger, fontSize: 13)),
                                ),
                                const SizedBox(height: 16),
                              ],
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                    backgroundColor: telegramBlue,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size.fromHeight(54),
                                    shape: const StadiumBorder(),
                                    textStyle: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: KaGoWeight.extraBold)),
                                onPressed: onContinue,
                                icon: const Icon(Icons.telegram, size: 24),
                                label: Text(tr('Продолжить с Telegram')),
                              ),
                            ]),
                ),
                const SizedBox(height: 22),
                Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Icon(Icons.lock_outline_rounded, size: 14, color: p.muted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(tr('Вход через официальный сайт Telegram'),
                        style: TextStyle(fontSize: 12, color: p.muted)),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Telegram and KAGO marks side by side, slightly overlapping.
class _PairedMarks extends StatelessWidget {
  const _PairedMarks();

  @override
  Widget build(BuildContext context) {
    const size = 76.0;
    final p = context.kago;
    // An outer ring in the page colour separates the overlapping circles.
    Widget circle(Widget child, Color color, {Color? outline}) => Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: p.canvas, shape: BoxShape.circle),
          child: Container(
            decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: outline == null ? null : Border.all(color: outline)),
            alignment: Alignment.center,
            child: child,
          ),
        );
    return SizedBox(
      width: size * 2 - 18,
      height: size,
      child: Stack(children: <Widget>[
        Positioned(
            left: 0,
            child: circle(
                // Telegram's paper plane, pointing up and to the right.
                Transform.translate(
                    offset: const Offset(-2, 1),
                    child: Transform.rotate(
                        angle: -.45,
                        child: const Icon(Icons.send_rounded,
                            color: Colors.white, size: 38))),
                telegramBlue)),
        Positioned(
            right: 0,
            // The mark's own navy tile, so its corners blend into the circle.
            child: circle(
                const KagoLogo(size: size * .6), const Color(0xFF1A4780),
                outline: p.border)),
      ]),
    );
  }
}
