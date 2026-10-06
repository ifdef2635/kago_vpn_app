/// What the in-app usekago.net WebView does with a navigation.
enum SiteNavigation {
  /// Load inside the WebView.
  allow,

  /// Hand to the system (Telegram app, browser).
  external,

  /// Refuse.
  block,
}

/// Navigation rules for the usekago.net WebView (Telegram sign-in). The
/// WebView carries the site session and a JavaScript bridge that logs the app
/// in, so only the site and Telegram's login pages load inside it; other
/// HTTPS pages open in the browser, and only Telegram links (`tg:`) may start
/// another app. Everything else (`file:`, `content:`, `javascript:`, `data:`,
/// `intent:` to arbitrary components, plain `http:`) is refused.
abstract final class SiteNavigationPolicy {
  /// usekago.net and its subdomains — exact match, so `evilusekago.net` or
  /// `usekago.net.example.com` are not the site.
  static bool isKagoHost(String host) {
    final value = host.toLowerCase();
    return value == 'usekago.net' || value.endsWith('.usekago.net');
  }

  static bool isTelegramHost(String host) {
    final value = host.toLowerCase();
    return value == 'telegram.org' || value.endsWith('.telegram.org');
  }

  /// HTTPS page of the site itself (default port), the only origin allowed to
  /// call the app's JavaScript handler.
  static bool isKagoOrigin(Uri url) =>
      url.scheme.toLowerCase() == 'https' &&
      isKagoHost(url.host) &&
      (!url.hasPort || url.port == 443);

  /// Decision for a top-level navigation (main frame or popup).
  static SiteNavigation decide(Uri url) {
    switch (url.scheme.toLowerCase()) {
      case 'about':
        // New popups start on about:blank.
        return url.toString() == 'about:blank'
            ? SiteNavigation.allow
            : SiteNavigation.block;
      case 'https':
        if (url.host.isEmpty) return SiteNavigation.block;
        return isKagoHost(url.host) || isTelegramHost(url.host)
            ? SiteNavigation.allow
            : SiteNavigation.external;
      case 'tg':
        return SiteNavigation.external;
      default:
        return SiteNavigation.block;
    }
  }

  /// Subframes (Cloudflare challenge, Telegram widget): HTTPS only.
  static bool allowSubframe(Uri url) {
    final scheme = url.scheme.toLowerCase();
    return scheme == 'https' ||
        (scheme == 'about' && url.toString() == 'about:blank');
  }

  /// `intent://resolve?domain=x#Intent;scheme=tg;package=…;end` → `tg://…`.
  /// Only Telegram intents are turned into links: an intent URL can name any
  /// app component, so nothing else is started from it.
  static Uri? telegramFromIntent(String link) {
    final scheme = intentExtra(link, 'scheme')?.toLowerCase();
    final hash = link.indexOf('#Intent');
    if (scheme != 'tg' || hash < 'intent://'.length) return null;
    final target = Uri.tryParse('tg://${link.substring(9, hash)}');
    return target != null && target.scheme == 'tg' ? target : null;
  }

  /// The browser fallback of an intent URL, if it is an HTTPS address.
  static Uri? intentFallback(String link) {
    final value = intentExtra(link, 'S.browser_fallback_url');
    final url = value == null ? null : Uri.tryParse(value);
    return url != null && url.scheme == 'https' && url.host.isNotEmpty
        ? url
        : null;
  }

  static String? intentExtra(String link, String key) {
    final hash = link.indexOf('#Intent;');
    if (hash < 0) return null;
    for (final part in link.substring(hash + 8).split(';')) {
      if (part.startsWith('$key=')) {
        try {
          return Uri.decodeComponent(part.substring(key.length + 1));
        } on ArgumentError {
          return null;
        }
      }
    }
    return null;
  }
}
