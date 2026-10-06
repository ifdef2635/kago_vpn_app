import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage shared by the app (session cookies, profiles, controller
/// secret, device id).
///
/// On macOS the data-protection keychain needs a keychain-access-groups
/// entitlement with an Apple Developer team, which the ad-hoc signed .dmg
/// build does not have (reads and writes would fail with -34018). The login
/// keychain works without it.
const kagoSecureStorage = FlutterSecureStorage(
  mOptions: MacOsOptions(useDataProtectionKeyChain: false),
);
