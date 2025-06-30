export 'package:lualike/testing.dart';
export 'bridge_assert.dart';
// ignore: depend_on_referenced_packages
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
