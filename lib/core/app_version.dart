/// App version for the User-Agent and the update check;
/// `test/user_agent_test.dart` keeps it in step with pubspec.yaml.
///
/// Its own file so a version bump (this file and pubspec.yaml) does not
/// start the Android and macOS check builds (`paths` in their workflows).
const kagoAppVersion = '2.6.2';
