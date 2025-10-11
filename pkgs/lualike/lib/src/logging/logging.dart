export 'logger.dart';

import 'package:contextual/contextual.dart' as ctx;
import 'package:lualike/src/logging/logger.dart';
import 'package:lualike/src/utils/platform_utils.dart' as platform;

List<String> _splitCategories(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  return value
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Sets up logging for LuaLike, using environment variables or explicit arguments.
///
/// Environment variables:
///   LOGGING_ENABLED: 'true' or 'false' (default: false)
///   LOGGING_LEVEL: Level name (contextual or legacy):
///     debug/info/warning/error/critical/alert/emergency
///     or legacy FINE/INFO/WARNING/SEVERE/SHOUT/CONFIG
///   LOGGING_CATEGORY: Comma-separated categories
///
/// Args override environment variables if provided.
void setLualikeLogging({
  bool? enabled,
  ctx.Level? level,
  String? category,
  List<String>? categories,
  String? backend, // 'contextual' (default) or 'basic'
  bool? pretty,
}) {
  final String envValue =
      (platform.getEnvironmentVariable('LOGGING_ENABLED') ?? '')
          .trim()
          .toLowerCase();
  final envEnabled = envValue == 'true' || envValue == '1';

  final envLevel = platform.getEnvironmentVariable('LOGGING_LEVEL');
  final envCategory = platform.getEnvironmentVariable('LOGGING_CATEGORY');
  final envBackend = platform.getEnvironmentVariable('LOGGING_BACKEND');
  final envPretty = platform.getEnvironmentVariable('LOGGING_PRETTY');

  final bool useEnabled = (enabled ?? false) || envEnabled;

  // Default to DEBUG when enabled, INFO otherwise. Synonyms supported.
  ctx.Level useLevel = useEnabled ? ctx.Level.debug : ctx.Level.info;

  // Environment variable can override the default.
  if (envLevel != null) {
    final parsed = parseLogLevel(envLevel);
    if (parsed != null) useLevel = parsed;
  }

  // Command-line argument has the highest precedence.
  if (level != null) {
    useLevel = level;
  }

  // Categories: combine CLI list, single category, and env list.
  final combinedCats = <String>{};
  if (categories != null) combinedCats.addAll(categories);
  if (category != null && category.isNotEmpty) combinedCats.add(category);
  combinedCats.addAll(_splitCategories(envCategory));

  Logger.initialize();
  // Select backend (default to contextual)
  final useBackend = (backend ?? envBackend ?? 'contextual')
      .toLowerCase()
      .trim();
  final usePretty =
      (pretty ??
          ((envPretty ?? '').isEmpty
              ? null
              : ((envPretty!.toLowerCase().trim() == 'true') ||
                    (envPretty.toLowerCase().trim() == '1')))) ??
      true;
  if (useBackend == 'contextual') {
    Logger.useContextualBackend(pretty: usePretty);
  }
  Logger.setEnabled(useEnabled);
  Logger.setLevelFilter(useLevel);
  if (combinedCats.isEmpty) {
    Logger.setCategoryFilters(null);
  } else {
    Logger.setCategoryFilters(combinedCats);
  }

  if (useEnabled) {
    final catsText = combinedCats.isEmpty ? '' : ' ${combinedCats.join(',')}';
    print('Logging with: ${levelName(useLevel)}$catsText');
  }
}

/// Parse level names from CLI/env supporting both contextual and legacy names.
/// Examples: debug, info, warning, error, alert, notice, FINE, INFO, WARNING, SEVERE, SHOUT, CONFIG
ctx.Level? parseLogLevel(String name) {
  final n = name.trim().toUpperCase();
  switch (n) {
    case 'DEBUG':
    case 'FINE':
    case 'FINER':
    case 'FINEST':
    case 'ALL':
      return ctx.Level.debug;
    case 'INFO':
      return ctx.Level.info;
    case 'WARNING':
      return ctx.Level.warning;
    case 'ERROR':
    case 'SEVERE':
      return ctx.Level.error;
    case 'CRITICAL':
      return ctx.Level.critical;
    case 'ALERT':
    case 'SHOUT':
      return ctx.Level.alert;
    case 'EMERGENCY':
      return ctx.Level.emergency;
    case 'NOTICE':
    case 'CONFIG':
      return ctx.Level.notice;
    case 'OFF':
      return null;
    default:
      return null;
  }
}

String levelName(ctx.Level level) {
  switch (level) {
    case ctx.Level.debug:
      return 'DEBUG';
    case ctx.Level.notice:
      return 'NOTICE';
    case ctx.Level.info:
      return 'INFO';
    case ctx.Level.warning:
      return 'WARNING';
    case ctx.Level.error:
      return 'ERROR';
    case ctx.Level.critical:
      return 'CRITICAL';
    case ctx.Level.alert:
      return 'ALERT';
    case ctx.Level.emergency:
      return 'EMERGENCY';
  }
}
