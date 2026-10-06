import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/network/mihomo_macos.dart';
import 'package:kago_vpn/core/network/mihomo_windows_system_proxy.dart';

void main() {
  test('network services: skips the note and disabled services', () {
    const output = '''
An asterisk (*) denotes that a network service is disabled.
Wi-Fi
*Thunderbolt Bridge
USB 10/100/1000 LAN

''';
    expect(MihomoMacosSystemProxy.parseServices(output),
        <String>['Wi-Fi', 'USB 10/100/1000 LAN']);
  });

  test('bypass list includes Russian sites only when asked', () {
    final plain = MihomoMacosSystemProxy.bypassFor(bypassRussian: false);
    final russian = MihomoMacosSystemProxy.bypassFor(bypassRussian: true);
    expect(plain, contains('localhost'));
    expect(plain, isNot(contains('*.ru')));
    expect(russian, containsAll(MihomoWindowsSystemProxy.russianBypass));
  });

  test('DNS servers: addresses or empty for DHCP', () {
    expect(
        MihomoMacosSystemProxy.parseDnsServers('192.168.1.1\n1.1.1.1\n'),
        <String>['192.168.1.1', '1.1.1.1']);
    expect(
        MihomoMacosSystemProxy.parseDnsServers(
            "There aren't any DNS Servers set on Wi-Fi.\n"),
        isEmpty);
  });

  test('root core: only root:admin setuid, not writable by others', () {
    expect(MihomoMacosCore.isPrivilegedStat('root:admin -rwsr-x---\n'), isTrue);
    expect(MihomoMacosCore.isPrivilegedStat('root:admin -rwsr-xr-x'), isTrue);
    expect(MihomoMacosCore.isPrivilegedStat('user:staff -rwxr-xr-x'), isFalse);
    expect(MihomoMacosCore.isPrivilegedStat('root:admin -rwxr-xr-x'), isFalse);
    expect(MihomoMacosCore.isPrivilegedStat('root:admin -rwsrwxr-x'), isFalse);
    expect(MihomoMacosCore.isPrivilegedStat('root:admin -rwsr-xrwx'), isFalse);
  });

  test('admin script quotes paths for the shell and AppleScript', () {
    final path = MihomoMacosCore.shellQuote(
        "/Users/o'neil/Library/Application Support/x");
    expect(path, r"'/Users/o'\''neil/Library/Application Support/x'");
    final script = MihomoMacosCore.adminScript('chmod 4750 $path', 'Say "hi"');
    expect(script, startsWith('do shell script "chmod 4750 '));
    expect(script, contains(r"o'\\''neil"));
    expect(script, contains(r'with prompt "Say \"hi\""'));
    expect(script, endsWith('with administrator privileges'));
  });
}
