import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final androidVpnEventProvider = StreamProvider<Map<String, dynamic>>((ref) {
  const channel = EventChannel('net.usekago.vpn/events');
  return channel.receiveBroadcastStream().where((event) => event is Map).map(
        (event) => Map<String, dynamic>.from(event as Map<dynamic, dynamic>),
      );
});
