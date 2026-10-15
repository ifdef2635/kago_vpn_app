/// An automatic retry cannot show UAC or a password prompt.
class CoreAuthorizationRequired implements Exception {
  const CoreAuthorizationRequired(this.message);

  final String message;

  @override
  String toString() => message;
}
