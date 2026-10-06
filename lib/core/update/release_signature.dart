import 'package:crypto/crypto.dart';

/// Public key of the release signing key (RSA-4096): the same key that signs
/// the Android APK (certificate "CN=KaGo VPN, O=usekago.net", SHA-256
/// 4B:98:C1:88:3F:16:E3:64:E8:31:CA:B1:C4:99:58:43:80:DE:41:B0:05:35:93:58:7E:CA:66:8A:6C:36:1E:C0).
/// release.yml signs SHA256SUMS.txt with it; the app installs an update only
/// if that signature checks out, so a release published by anyone without
/// the key (a stolen GitHub token, a compromised workflow) is refused.
const releaseSigningModulusHex =
    'd0c82651d89fbc0236f338c556dd6ce70c2f73def33b37968f76394780e41d2d'
    'f79644b5fab03d4df1ba4df1bd23435561fbfd2772d4865f56e2a843106a1b58'
    'bdb6f2bc31487a768078469726bd73d317467c9e272028f142e1f0ef6095be7e'
    'd8306d535730520a839cf8728f0153a8b55cefad143c6cce480b4aea2ef795de'
    '671c18bf937c31d8a1f540862df7fa50969695761dd1c197931238b8a4c86c86'
    '20ac3b0f0dfce872b522092f8c44dd462d1243ae4b25a74f1eb37c2b687d077d'
    'fcc1f2490a719769946dd5206ac8fcefd0b3025f844c2ce84f64e13a50602fe8'
    'e1718338931e68b5669b38f7f5ea718d898621f3cd3bef6edd7c105ec08d4a28'
    'a683761beb14a28ebc84f489fda6a0a03fb469a5dddcb07ca1131bae089dd12c'
    '1bf1e943913d094bf04b34d211531d76e5d6124cdf0c758d3a203dd3b64466fe'
    'c6c9cfbf4b80de089d5e304b1e13bf3a51321ef79a5f789db6ecb444effd5893'
    '9effbc9e6262f4005a491fa2e659d2870750c82105d06c1850366420314a7ef8'
    '4493f6a4d7bca2d00527d66cccfbb823915c45b8912de371551ee0c469469a44'
    '70c553df9f5a7b6ea45faae11fec7fef34c8acbe8f604578780adf500a6ea205'
    '277843ca3021f20c39d5158b567a16ac695dbed22bf312fcb1a6c5248d913d5f'
    '95fec69f36db504a63995cc3454a8057e20b2e87e2ced9f086561ec4b7ac2d53';
const releaseSigningExponent = 65537;

/// DER prefix of DigestInfo for SHA-256 (RFC 8017, section 9.2, note 1).
const _sha256DigestInfo = <int>[
  0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, //
  0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
];

/// RSASSA-PKCS1-v1_5 with SHA-256: true if [signature] signs [message] under
/// the key (modulus as hex, public exponent). The expected encoded message is
/// built and compared byte by byte, so the decrypted block is never parsed.
bool verifyRsaSha256(List<int> message, List<int> signature,
    {String modulusHex = releaseSigningModulusHex,
    int exponent = releaseSigningExponent}) {
  final modulus = BigInt.parse(modulusHex, radix: 16);
  final size = (modulus.bitLength + 7) ~/ 8;
  if (signature.length != size) return false;
  final s = _toBigInt(signature);
  if (s >= modulus) return false;
  final em = _toBytes(s.modPow(BigInt.from(exponent), modulus), size);
  final t = <int>[..._sha256DigestInfo, ...sha256.convert(message).bytes];
  if (size < t.length + 11) return false;
  final expected = <int>[
    0x00,
    0x01,
    for (var i = 0; i < size - t.length - 3; i++) 0xff,
    0x00,
    ...t,
  ];
  var diff = 0;
  for (var i = 0; i < size; i++) {
    diff |= em[i] ^ expected[i];
  }
  return diff == 0;
}

BigInt _toBigInt(List<int> bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

List<int> _toBytes(BigInt value, int size) {
  final out = List<int>.filled(size, 0);
  var rest = value;
  for (var i = size - 1; i >= 0; i--) {
    out[i] = (rest & BigInt.from(0xff)).toInt();
    rest = rest >> 8;
  }
  return out;
}
