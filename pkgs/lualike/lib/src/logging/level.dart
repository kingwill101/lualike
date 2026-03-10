library;

enum Level {
  emergency,
  alert,
  critical,
  error,
  warning,
  notice,
  info,
  debug;

  @override
  String toString() => name.toUpperCase();
}
