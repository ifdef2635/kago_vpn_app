import 'package:yaml/yaml.dart';

class SubscriptionMetadata {
  const SubscriptionMetadata(
      {required this.serviceName,
      required this.headers,
      required this.proxyGroupNames,
      this.supportUrl,
      this.buyPlanUrl,
      this.buyTrafficUrl,
      this.newDomain});
  final String serviceName;
  final Map<String, String> headers;
  final List<String> proxyGroupNames;
  final String? supportUrl;
  final String? buyPlanUrl;
  final String? buyTrafficUrl;
  final String? newDomain;

  static SubscriptionMetadata parse(
      {required String yaml,
      required Map<String, List<String>> responseHeaders}) {
    final headers = <String, String>{};
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
      supportUrl: value('support-url') ?? value('supporturl'),
      buyPlanUrl: value('flclashx-buyplan'),
      buyTrafficUrl: value('flclashx-buytraffic'),
      newDomain: value('flclashx-newdomain'),
    );
  }
}
