// Re-export shared types and platform-specific implementations
export 'io_device_shared.dart';
export 'io_device_io.dart' if (dart.library.html) 'io_device_web.dart';
