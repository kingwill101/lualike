import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.event Flame input integration', () {
    test('queues focus, keyboard, text, and pointer events', () async {
      final host = LoveHeadlessHost();
      final runtime = LoveScriptRuntime(host: host);
      final adapter = LoveFlameInputAdapter(
        host: host,
        runtimeProvider: () => runtime,
      );

      adapter.handleFocusChanged(true);
      adapter.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          character: 'a',
          timeStamp: Duration.zero,
        ),
      );
      adapter.handlePointerEnter(
        const PointerEnterEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(3, 4),
        ),
      );
      adapter.handlePointerDown(
        const PointerDownEvent(
          kind: PointerDeviceKind.mouse,
          pointer: 21,
          position: Offset(10.9, 20.1),
          buttons: kPrimaryMouseButton,
        ),
      );
      await adapter.flush();

      final poll = await _call(runtime, const ['love', 'event', 'poll']);
      expect(poll, isA<BuiltinFunction>());
      final iterator = poll! as BuiltinFunction;

      expect(await _callCallable(iterator), <Object?>['focus', true]);
      expect(await _callCallable(iterator), <Object?>[
        'keypressed',
        'a',
        'a',
        false,
      ]);
      expect(await _callCallable(iterator), <Object?>['textinput', 'a']);
      expect(await _callCallable(iterator), <Object?>['mousefocus', true]);
      expect(await _callCallable(iterator), <Object?>[
        'mousepressed',
        10.0,
        20.0,
        1,
        false,
        1,
      ]);
      expect(await _callCallable(iterator), isNull);
    });
  });
}

Future<Object?> _call(
  LoveScriptRuntime runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
}

Future<Object?> _callCallable(
  BuiltinFunction function, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(function.call(args));
}

BuiltinFunction _rawFunction(LoveScriptRuntime runtime, List<String> path) {
  var current = runtime.runtime.getCurrentEnv().get(path.first);
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
