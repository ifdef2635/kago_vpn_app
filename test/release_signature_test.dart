import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/update/release_signature.dart';

// A throwaway RSA-2048 test key (openssl genrsa) and its signature of
// [_message] (openssl dgst -sha256 -sign).
const _testModulus =
    'c701098efcc060e86a0ec5160b1ef9b414f870312409a3ba4e06b372d04901b2'
    '5bb94d997dba0a98bf1f3b0a4adbb6333360359f84f537bf985b41da03459a71'
    '4d44127e5b89e741bb18fec2ee1985f4478abe3a34597dea108ca07bd357874c'
    '4b3b55f72ce8bb2b039336f8e19983f25e087709dc1368f4a8fa7d38f3d0c3a7'
    '2ea23ebc83b9af594a68f720ddc68b04cf1b1f2b9ca110ffedbf840b8db929dc'
    '472fc341096135e4fe6b41f9a884a96e40f0bed520bbcb645d1ccff5baf8e64b'
    'edf3c680681b8df93817cb5514bb73a3f641d144092de04cf2e5e4a626e5a2ba'
    '166ce5ceaf8fca259f5a0f0d14dde56eaedd99ac5170488c0aaae13b11ed282b';
const _testSignature =
    '0ac39188875dcb45daa70ccebd2d3f049dd00db92d5680a9b3e1ff16ee54b4e0'
    'e3cff0d3f4905f534e2ee2dc60e443dab38373432e0d85603e00e032979c2f66'
    '39d9f47b1b2ee6f784fb3b7b8dedcf611b3cd97d0e5b723755fad45a871c6e26'
    'a8dd77344710aca51b256bbf517fd242c1c41ffa807f0f98d07e8c9a143d6700'
    'a177456b779de09f7a3625f88ddc98c84bb90f8b5c7c4a38207a22e49a874966'
    '78e2834b7be0be0e1c5cb728a89768f409151575787a5edacc0e8caa3846c4ba'
    '1b51bcaba40bb616beb972aee8c53af914ba720d3ea1db956df7bddf8d138605'
    'bdaa57657cd834cf51e61b9d395d8a2218aff49a42803d0120a8e51237a069b5';
const _message = 'aaaa  KaGoVPN-Android-1.0.5.apk\n';

List<int> _hex(String hex) => <int>[
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];

void main() {
  test('accepts a valid signature', () {
    expect(
        verifyRsaSha256(utf8.encode(_message), _hex(_testSignature),
            modulusHex: _testModulus),
        isTrue);
  });

  test('refuses a changed file list or signature', () {
    expect(
        verifyRsaSha256(
            utf8.encode(_message.replaceFirst('a', 'b')), _hex(_testSignature),
            modulusHex: _testModulus),
        isFalse);
    final broken = _hex(_testSignature)..[10] ^= 1;
    expect(
        verifyRsaSha256(utf8.encode(_message), broken,
            modulusHex: _testModulus),
        isFalse);
    expect(
        verifyRsaSha256(utf8.encode(_message), _hex(_testSignature).sublist(1),
            modulusHex: _testModulus),
        isFalse);
  });

  test('a signature by another key is refused by the release key', () {
    expect(
        verifyRsaSha256(utf8.encode(_message), _hex(_testSignature)), isFalse);
    expect(BigInt.parse(releaseSigningModulusHex, radix: 16).bitLength, 4096);
  });
}
