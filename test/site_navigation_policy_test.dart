import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/features/account/site_navigation_policy.dart';

void main() {
  SiteNavigation decide(String url) =>
      SiteNavigationPolicy.decide(Uri.parse(url));

  test('only the real site may call the login bridge', () {
    bool origin(String url) =>
        SiteNavigationPolicy.isKagoOrigin(Uri.parse(url));
    expect(origin('https://usekago.net'), isTrue);
    expect(origin('https://www.usekago.net/login'), isTrue);
    expect(origin('https://evilusekago.net'), isFalse);
    expect(origin('https://usekago.net.evil.com'), isFalse);
    expect(origin('http://usekago.net'), isFalse);
    expect(origin('https://usekago.net:8443'), isFalse);
  });

  test('site and Telegram load inside, other pages go to the browser', () {
    expect(decide('https://usekago.net/my'), SiteNavigation.allow);
    expect(decide('https://oauth.telegram.org/auth?x=1'), SiteNavigation.allow);
    expect(decide('about:blank'), SiteNavigation.allow);
    expect(decide('https://example.com/'), SiteNavigation.external);
    expect(decide('https://evilusekago.net/'), SiteNavigation.external);
    expect(decide('tg://resolve?domain=kagovpnbot'), SiteNavigation.external);
  });

  test('dangerous schemes are refused', () {
    for (final url in <String>[
      'http://usekago.net/my',
      'file:///data/data/net.usekago.app/shared_prefs/x.xml',
      'content://net.usekago.app.updates/x.apk',
      'javascript:alert(1)',
      'data:text/html,<h1>x</h1>',
      'market://details?id=x',
      'sms:+100',
      'about:srcdoc',
    ]) {
      expect(decide(url), SiteNavigation.block, reason: url);
    }
  });

  test('intent URLs: only Telegram, fallback only over HTTPS', () {
    expect(
        SiteNavigationPolicy.telegramFromIntent(
            'intent://resolve?domain=kagovpnbot#Intent;scheme=tg;package=org.telegram.messenger;end'),
        Uri.parse('tg://resolve?domain=kagovpnbot'));
    expect(
        SiteNavigationPolicy.telegramFromIntent(
            'intent://evil#Intent;scheme=file;end'),
        isNull);
    expect(
        SiteNavigationPolicy.telegramFromIntent(
            'intent://x#Intent;component=com.victim/.Exported;end'),
        isNull);
    expect(
        SiteNavigationPolicy.intentFallback(
            'intent://x#Intent;scheme=tg;S.browser_fallback_url=https%3A%2F%2Ft.me%2Fkagovpnbot;end'),
        Uri.parse('https://t.me/kagovpnbot'));
    expect(
        SiteNavigationPolicy.intentFallback(
            'intent://x#Intent;S.browser_fallback_url=javascript%3Aalert(1);end'),
        isNull);
  });

  test('subframes: HTTPS only', () {
    expect(
        SiteNavigationPolicy.allowSubframe(
            Uri.parse('https://challenges.cloudflare.com/x')),
        isTrue);
    expect(
        SiteNavigationPolicy.allowSubframe(Uri.parse('javascript:x')), isFalse);
    expect(
        SiteNavigationPolicy.allowSubframe(Uri.parse('http://a.b/')), isFalse);
  });
}
