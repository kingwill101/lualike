import 'dart:async';

import 'package:lualike_test/test.dart';

void main() {
  group('Error reporting', () {
    test('reports LuaError only once', () async {
      final interpreter = Interpreter();
      final error = LuaError('boom');

      final printed = <String>[];

      await runZoned(
        () async {
          interpreter.reportError('boom', error: error);
          interpreter.reportError('boom', error: error);
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            printed.add(line);
          },
        ),
      );

      expect(printed.length, equals(2));
      expect(printed.first, contains('boom'));
      expect(printed.last, contains('stack traceback:'));

      final secondError = LuaError('second');
      printed.clear();

      await runZoned(
        () async {
          interpreter.reportError('second', error: secondError);
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            printed.add(line);
          },
        ),
      );

      expect(printed.length, equals(2));
      expect(printed.first, contains('second'));
    });
  });
}
