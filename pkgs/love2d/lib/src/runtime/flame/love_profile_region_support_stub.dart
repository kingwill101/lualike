final class LoveProfileRegionConfigurationException implements Exception {
  const LoveProfileRegionConfigurationException(this.message);

  final String message;

  @override
  String toString() => 'LoveProfileRegionConfigurationException: $message';
}

final class LoveProfileRegionHandle {
  const LoveProfileRegionHandle();

  Future<void> stop() async {}
}

Future<T> runLoveProfileRegion<T>(
  String name,
  Future<T> Function() body, {
  Map<String, String> attributes = const <String, String>{},
}) {
  return body();
}

Future<LoveProfileRegionHandle> startLoveProfileRegion(
  String name, {
  Map<String, String> attributes = const <String, String>{},
}) async {
  return const LoveProfileRegionHandle();
}
