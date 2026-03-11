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

    test('reports semantic-check failures through Lua-style reporter', () async {
      final bridge = LuaLike();
      final buffer = StringBuffer();

      await runZoned(
        () async {
          try {
            await bridge.execute('global none\nx = 1', scriptPath: 'main.lua');
            fail('expected error');
          } catch (_) {}
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            buffer.writeln(line);
          },
        ),
      );

      final output = buffer.toString();
      expect(output, contains('main.lua:2'));
      expect(output, contains("variable 'x' not declared"));
    });
  });
}
