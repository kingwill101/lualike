export 'package:lualike/testing.dart';
export 'bridge_assert.dart';
export 'package:test/test.dart';

final loggingEnabled = bool.fromEnvironment(
  'LOGGING_ENABLED',
  defaultValue:
      String.fromEnvironment(
        'LOGGING_ENABLED',
        defaultValue: 'false',
      ).toLowerCase() !=
      'false',
);
