import 'package:devtools_region_profiler/devtools_region_profiler.dart';

final class LoveProfileRegionConfigurationException implements Exception {
  const LoveProfileRegionConfigurationException(this.message);

  final String message;

  @override
  String toString() => 'LoveProfileRegionConfigurationException: $message';
}

final class LoveProfileRegionHandle {
  const LoveProfileRegionHandle._(this._delegate);

  final ProfileRegionHandle _delegate;

  Future<void> stop() => _delegate.stop();
}

Future<T> runLoveProfileRegion<T>(
  String name,
  Future<T> Function() body, {
  Map<String, String> attributes = const <String, String>{},
}) async {
  try {
    return await profileRegion<T>(name, body, attributes: attributes);
  } on ProfileRegionConfigurationException catch (error) {
    throw LoveProfileRegionConfigurationException(error.message);
  }
}

Future<LoveProfileRegionHandle> startLoveProfileRegion(
  String name, {
  Map<String, String> attributes = const <String, String>{},
}) async {
  try {
    return LoveProfileRegionHandle._(
      await startProfileRegion(name, attributes: attributes),
    );
  } on ProfileRegionConfigurationException catch (error) {
    throw LoveProfileRegionConfigurationException(error.message);
  }
}
