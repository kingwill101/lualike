import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/library_builder.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

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
            final result = await _call(
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
            final result = await _call(
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
            final cursor = await _call(
              runtime,
              const ['love', 'mouse', 'getSystemCursor'],
              <Object?>[cursorType],
            );
            expect(
              cursor,
              isNotNull,
              reason: 'Cursor "$cursorType" should exist',
            );
            expect(await _callMethod(cursor!, 'getType'), cursorType);
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

Future<Object?> _call(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
}

Future<Object?> _callMethod(
  Object object,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  final table = object is Value ? object.raw : object;
  expect(table, isA<Map>());

  final methodValue = (table as Map)[method];
  final callable = switch (methodValue) {
    final Value value => value.raw,
    final BuiltinFunction function => function,
    _ => methodValue,
  };
  expect(callable, isA<BuiltinFunction>());
  return _resolveCallResult(
    (callable as BuiltinFunction).call(<Object?>[object, ...args]),
  );
}

BuiltinFunction _rawFunction(Interpreter runtime, List<String> path) {
  var current = runtime.getCurrentEnv().get(path.first);
  for (final segment in path.skip(1)) {
    final table = current is Value ? current.raw : current;
    expect(
      table,
      isA<Map>(),
      reason: 'Expected ${path.join('.')} to traverse a Lua table',
    );
    current = (table as Map)[segment];
  }

  expect(current, isA<Value>());
  final raw = (current! as Value).raw;
  expect(raw, isA<BuiltinFunction>());
  return raw as BuiltinFunction;
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;

  if (resolved case final Value wrapped when wrapped.isMulti) {
    return (wrapped.raw as List<Object?>).map(_unwrap).toList(growable: false);
  }

  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
