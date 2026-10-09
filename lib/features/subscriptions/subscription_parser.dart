import 'package:yaml/yaml.dart';

class SubscriptionMetadata {
  const SubscriptionMetadata(
      {required this.serviceName,
      required this.headers,
      required this.proxyGroupNames,
      this.supportUrl,
      this.updateInterval,
      this.buyPlanUrl,
      this.buyTrafficUrl,
      this.newDomain});
  final String serviceName;
  final Map<String, String> headers;
  final List<String> proxyGroupNames;
  final String? supportUrl;

  /// `profile-update-interval` (hours): how often the provider wants the
  /// subscription re-downloaded.
  final Duration? updateInterval;
  final String? buyPlanUrl;
  final String? buyTrafficUrl;
  final String? newDomain;

  static SubscriptionMetadata parse(
      {required String yaml,
      required Map<String, List<String>> responseHeaders}) {
    final headers = <String, String>{};
    String? standard(String key) {
      for (final entry in responseHeaders.entries) {
        if (entry.key.toLowerCase() == key) {
          final value = entry.value.join(',').trim();
          return value.isEmpty ? null : value;
        }
      }
      return null;
    }

    for (final entry in responseHeaders.entries) {
      if (entry.key.toLowerCase().startsWith('flclashx-')) {
        headers[entry.key.toLowerCase()] = entry.value.join(',');
      }
    }
    final document = loadYaml(yaml);
    final root = document is YamlMap ? document : YamlMap();
    final groups = root['proxy-groups'];
    final names = groups is YamlList
        ? groups
            .whereType<YamlMap>()
            .map((group) => group['name'])
            .whereType<String>()
            .toList(growable: false)
        : const <String>[];
    String? value(String key) =>
        headers[key]?.trim().isNotEmpty == true ? headers[key]!.trim() : null;
    return SubscriptionMetadata(
      serviceName: value('flclashx-servicename') ?? 'KaGo VPN',
      headers: Map<String, String>.unmodifiable(headers),
      proxyGroupNames: names,
      supportUrl: httpsUrl(standard('support-url') ?? standard('supporturl')),
      updateInterval: updateIntervalOf(standard('profile-update-interval')),
      buyPlanUrl: value('flclashx-buyplan'),
      buyTrafficUrl: value('flclashx-buytraffic'),
      newDomain: value('flclashx-newdomain'),
    );
  }
}

/// [value] when it is an absolute https URL (a link the app may open).
String? httpsUrl(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  return uri != null && uri.scheme == 'https' && uri.hasAuthority
      ? uri.toString()
      : null;
}

/// `profile-update-interval: 6` (hours, as FlClash and Clash Verge read it).
/// Kept between 1 hour and 7 days; null when missing or not a number.
Duration? updateIntervalOf(String? value) {
  final hours = double.tryParse(value?.trim() ?? '');
  if (hours == null || hours.isNaN || hours <= 0) return null;
  final minutes = (hours * 60).round().clamp(60, 7 * 24 * 60);
  return Duration(minutes: minutes);
}
