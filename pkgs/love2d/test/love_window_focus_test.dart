import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.window focus queries', () {
    test('read explicit host focus state', () async {
      final runtime = Interpreter();
      final host = LoveHeadlessHost(
        windowHasFocus: true,
        windowHasMouseFocus: false,
      );

      installLove2d(runtime: runtime, host: host);

      expect(
        await _call(runtime, const ['love', 'window', 'hasFocus']),
        isTrue,
      );
      expect(
        await _call(runtime, const ['love', 'window', 'hasMouseFocus']),
        isFalse,
      );

      host.windowHasFocus = false;
      host.windowHasMouseFocus = true;

      expect(
        await _call(runtime, const ['love', 'window', 'hasFocus']),
        isFalse,
      );
      expect(
        await _call(runtime, const ['love', 'window', 'hasMouseFocus']),
        isTrue,
      );
    });

    test('follow Flame input adapter focus updates', () async {
      final runtime = Interpreter();
      final host = LoveHeadlessHost();
      final adapter = LoveFlameInputAdapter(
        host: host,
        runtimeProvider: () => null,
      );

      installLove2d(runtime: runtime, host: host);

      expect(
        await _call(runtime, const ['love', 'window', 'hasFocus']),
        isFalse,
      );
      expect(
        await _call(runtime, const ['love', 'window', 'hasMouseFocus']),
        isFalse,
      );

      adapter.handleFocusChanged(true);
      expect(
        await _call(runtime, const ['love', 'window', 'hasFocus']),
        isTrue,
      );

      adapter.handlePointerEnter(
        const PointerEnterEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(8, 13),
        ),
      );
      expect(
        await _call(runtime, const ['love', 'window', 'hasMouseFocus']),
        isTrue,
      );

      adapter.handlePointerExit(
        const PointerExitEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(8, 13),
        ),
      );
      expect(
        await _call(runtime, const ['love', 'window', 'hasMouseFocus']),
        isFalse,
      );

      adapter.handleFocusChanged(false);
      expect(
        await _call(runtime, const ['love', 'window', 'hasFocus']),
        isFalse,
      );
    });
  });
}

Future<Object?> _call(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
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
