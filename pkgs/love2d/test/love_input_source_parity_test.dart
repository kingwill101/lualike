import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('LOVE input source parity', () {
    late Interpreter runtime;
    late LoveHeadlessHost host;

    setUp(() {
      runtime = Interpreter();
      host = LoveHeadlessHost();
      installLove2d(runtime: runtime, host: host);
    });

    test(
      'accepts every key and scancode from the vendored LOVE source',
      () async {
        final source = File(
          'third_party/love/src/modules/keyboard/Keyboard.cpp',
        ).readAsStringSync();
        final keys = _extractCppEntries(source, 'Keyboard::keyEntries[]')
          ..sort();
        final scancodes = _extractCppEntries(
          source,
          'Keyboard::scancodeEntries[]',
        )..sort();

        for (final key in keys) {
          try {
            final result = await luaCall(
              runtime,
              const ['love', 'keyboard', 'getScancodeFromKey'],
              <Object?>[key],
            );
            expect(
              result,
              isA<String>(),
              reason: 'Key "$key" should be accepted',
            );
          } catch (error) {
            fail('Expected LOVE key constant "$key" to be accepted: $error');
          }
        }

        for (final scancode in scancodes) {
          try {
            final result = await luaCall(
              runtime,
              const ['love', 'keyboard', 'getKeyFromScancode'],
              <Object?>[scancode],
            );
            expect(
              result,
              isA<String>(),
              reason: 'Scancode "$scancode" should be accepted',
            );
          } catch (error) {
            fail('Expected LOVE scancode "$scancode" to be accepted: $error');
          }
        }
      },
    );

    test(
      'accepts every system cursor name from the vendored LOVE source',
      () async {
        final source = File(
          'third_party/love/src/modules/mouse/Cursor.cpp',
        ).readAsStringSync();
        final cursorTypes = _extractCppEntries(
          source,
          'Cursor::systemCursorEntries[]',
        )..sort();

        for (final cursorType in cursorTypes) {
          try {
            final cursor = await luaCall(
              runtime,
              const ['love', 'mouse', 'getSystemCursor'],
              <Object?>[cursorType],
            );
            expect(
              cursor,
              isNotNull,
              reason: 'Cursor "$cursorType" should exist',
            );
            expect(await luaCallMethod(cursor!, 'getType'), cursorType);
          } catch (error) {
            fail(
              'Expected LOVE system cursor "$cursorType" to be accepted: $error',
            );
          }
        }
      },
    );
  });
}

List<String> _extractCppEntries(String source, String marker) {
  final markerIndex = source.indexOf(marker);
  if (markerIndex == -1) {
    throw StateError('Could not find marker "$marker" in vendored LOVE source');
  }

  final blockStart = source.indexOf('{', markerIndex);
  final blockEnd = source.indexOf('};', blockStart);
  final block = source.substring(blockStart, blockEnd);
  final matches = RegExp(r'\{"((?:\\.|[^"])*)"\s*,').allMatches(block);
  return matches
      .map((match) => _decodeCppString(match.group(1)!))
      .toList(growable: false);
}

String _decodeCppString(String value) {
  return value.replaceAll(r'\"', '"').replaceAll(r'\\', '\\');
}
