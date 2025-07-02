export 'package:lualike/testing.dart';
export 'bridge_assert.dart';
// ignore: depend_on_referenced_packages
export 'package:test/test.dart';
export 'package:lualike/src/logger.dart';
export 'package:logging/logging.dart' show Level;

import 'package:lualike/src/logger.dart';
import 'package:logging/logging.dart' as pkg_logging;
import 'dart:io';

final loggingEnabled = bool.fromEnvironment(
  'LOGGING_ENABLED',
  defaultValue:
      String.fromEnvironment(
        'LOGGING_ENABLED',
        defaultValue: 'false',
      ).toLowerCase() !=
      'false',
);

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
  final envEnabled = Platform.environment['LOGGING_ENABLED'];
  final envLevel = Platform.environment['LOGGING_LEVEL'];
  final envCategory = Platform.environment['LOGGING_CATEGORY'];

  final bool useEnabled =
      enabled ??
      (envEnabled != null
          ? envEnabled.toLowerCase() != 'false' && envEnabled != ''
          : loggingEnabled);

  pkg_logging.Level useLevel = level ?? pkg_logging.Level.WARNING;
  if (envLevel != null) {
    useLevel = pkg_logging.Level.LEVELS.firstWhere(
      (lvl) => lvl.name.toUpperCase() == envLevel.toUpperCase(),
      orElse: () => useLevel,
    );
  }

  final String? useCategory = category ?? envCategory;

  // Enable logging if explicitly enabled, or if a level/category filter is set
  Logger.setEnabled(
    useEnabled ||
        level != null ||
        category != null ||
        envLevel != null ||
        envCategory != null,
  );
  Logger.setDefaultLevel(useLevel);
  Logger.setCategoryFilter(useCategory);
  Logger.setLevelFilter(useLevel);
}
