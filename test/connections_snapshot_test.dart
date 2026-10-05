import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/models/mihomo_models.dart';

void main() {
  test('parses cumulative traffic and live connections from /connections', () {
    final snapshot = ConnectionsSnapshot.fromJson(<String, dynamic>{
      'downloadTotal': 5242880,
      'uploadTotal': 1024,
      'connections': <dynamic>[
        <String, dynamic>{
          'id': 'a',
          'download': 10,
          'upload': 2,
          'rule': 'Match',
          'chains': <dynamic>['KaGo VPN', 'Node'],
          'metadata': <String, dynamic>{
            'host': 'example.org',
            'destinationIP': '93.184.216.34',
            'network': 'tcp',
          },
        },
      ],
    });

    expect(snapshot.downloadTotal, 5242880);
    expect(snapshot.uploadTotal, 1024);
    expect(snapshot.connections.single.host, 'example.org');
    expect(snapshot.downloadSpeed, 0);
  });

  test('mihomo returns "connections": null when idle', () {
    final snapshot = ConnectionsSnapshot.fromJson(<String, dynamic>{
      'downloadTotal': 0,
      'uploadTotal': 0,
      'connections': null,
    });

    expect(snapshot.connections, isEmpty);
  });

  test('withSpeed keeps totals and formats the speed per second', () {
    final snapshot = const ConnectionsSnapshot(
            connections: <ActiveConnection>[], downloadTotal: 7)
        .withSpeed(download: 1536, upload: 0);

    expect(snapshot.downloadTotal, 7);
    expect(formatSpeed(snapshot.downloadSpeed), '1.5 КБ/с');
    expect(formatSpeed(snapshot.uploadSpeed), '0 Б/с');
  });
}
