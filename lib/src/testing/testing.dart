import 'dart:io';

import 'package:logging/logging.dart' as pkg_logging;
import 'package:lualike/src/logger.dart';

export 'package:logging/logging.dart' show Level;
export 'package:lualike/src/logger.dart';
export 'package:lualike/testing.dart';
// ignore: depend_on_referenced_packages
export 'package:test/test.dart';

export 'bridge_assert.dart';

/// Sets up logging for LuaLike, using environment variables or explicit arguments.
///
/// Environment variables:
///   LOGGING_ENABLED: 'true' or 'false' (default: false)
///   LOGGING_LEVEL: Dart log level name (e.g., 'FINE', 'INFO', 'WARNING', 'SEVERE')
///
/// Args override environment variables if provided.
void setLualikeLogging({
  bool? enabled,
  pkg_logging.Level? level,
  String? category,
}) {
  final String envValue = (Platform.environment['LOGGING_ENABLED'] ?? '')
      .trim()
      .toLowerCase();
  final envEnabled = envValue == 'true' || envValue == '1';

  final envLevel = Platform.environment['LOGGING_LEVEL'];
  final envCategory = Platform.environment['LOGGING_CATEGORY'];

  final bool useEnabled = (enabled ?? false) || envEnabled;

  // Default to FINE when enabled, INFO otherwise. This allows --debug to show
  // fine-grained logs as intended, and fixes precedence of level sources.
  pkg_logging.Level useLevel = useEnabled
      ? pkg_logging.Level.FINE
      : pkg_logging.Level.INFO;

  // Environment variable can override the default.
  if (envLevel != null) {
    useLevel = pkg_logging.Level.LEVELS.firstWhere(
      (lvl) => lvl.name.toUpperCase() == envLevel.toUpperCase(),
      orElse: () => useLevel,
    );
  }

  // Command-line argument has the highest precedence.
  if (level != null) {
    useLevel = level;
  }

  final String? useCategory = category ?? envCategory;
  Logger.initialize(defaultLevel: useLevel);
  // Enable logging only if explicitly enabled. Providing a log level or category
  // only serves to filter logs when logging is active.
  Logger.setEnabled(useEnabled);
  Logger.setDefaultLevel(useLevel);
  Logger.setCategoryFilter(useCategory);
  Logger.setLevelFilter(useLevel);

  if (useEnabled) {
    print('Logging with: $useLevel ${useCategory ?? ''}'.trim());
  }
}
