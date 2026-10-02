import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/network/mihomo_controller.dart';
import 'package:kago_vpn/features/subscriptions/subscription_repository.dart';

void main() {
  group('Mihomo controller endpoint policy', () {
    test('allows local HTTP and remote HTTPS', () {
      expect(
        MihomoController.normalizeEndpoint('http://127.0.0.1:9090/'),
        'http://127.0.0.1:9090',
      );
      expect(
        MihomoController.normalizeEndpoint('https://controller.example.net'),
        'https://controller.example.net',
      );
    });

    test('rejects remote cleartext and URL-embedded credentials', () {
      expect(
        () =>
            MihomoController.normalizeEndpoint('http://controller.example.net'),
        throwsFormatException,
      );
      expect(
        () => MihomoController.normalizeEndpoint(
            'https://user:secret@controller.example.net'),
        throwsFormatException,
      );
    });
  });

  group('Subscription URL policy', () {
    test('allows HTTPS and loopback HTTP only', () {
      expect(
        SubscriptionRepository.validateSubscriptionUrl(
                'https://vpn.example.net/subscribe?token=abc')
            .scheme,
        'https',
      );
      expect(
        SubscriptionRepository.validateSubscriptionUrl(
                'http://localhost:8080/profile')
            .host,
        'localhost',
      );
    });

    test('rejects remote cleartext and embedded credentials', () {
      expect(
        () => SubscriptionRepository.validateSubscriptionUrl(
            'http://vpn.example.net/subscribe'),
        throwsFormatException,
      );
      expect(
        () => SubscriptionRepository.validateSubscriptionUrl(
            'https://user:secret@vpn.example.net/subscribe'),
        throwsFormatException,
      );
    });
  });
}
