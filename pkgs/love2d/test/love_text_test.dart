import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics Text bindings', () {
    test(
      'text methods follow LOVE replacement and indexing semantics',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[20],
        );
        final text = await _call(
          runtime,
          const ['love', 'graphics', 'newText'],
          <Object?>[font, 'Lua'],
        );

        expect(await _callMethod(text, 'getWidth', const <Object?>[1]), 36.0);
        expect(await _callMethod(text, 'getHeight', const <Object?>[1]), 20.0);
        expect(await _callMethod(text, 'getWidth'), 36.0);

        final appended = await _callMethod(text, 'add', const <Object?>[
          'body',
        ]);
        expect(appended, 2);
        expect(await _callMethod(text, 'getWidth', const <Object?>[2]), 48.0);
        expect(await _callMethod(text, 'getWidth'), 48.0);

        final wrapped = await _callMethod(text, 'addf', const <Object?>[
          'ab cd',
          24.0,
          'center',
        ]);
        expect(wrapped, 3);
        expect(
          await _callMethod(text, 'getDimensions', const <Object?>[3]),
          <Object?>[24.0, 40.0],
        );
        expect(await _callMethod(text, 'getWidth'), 24.0);
        expect(await _callMethod(text, 'getHeight'), 40.0);

        await _callMethod(text, 'set', const <Object?>['x']);
        expect(await _callMethod(text, 'getWidth', const <Object?>[1]), 12.0);
        expect(await _callMethod(text, 'getWidth', const <Object?>[2]), 0.0);

        final smallFont = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[10],
        );
        await _callMethod(text, 'setFont', <Object?>[smallFont]);
        final currentFont = await _callMethod(text, 'getFont');
        expect(await _callMethod(currentFont, 'getHeight'), 10.0);

        await _callMethod(text, 'setf', const <Object?>['ab cd', 12.0, 'left']);
        expect(await _callMethod(text, 'getDimensions'), <Object?>[12.0, 20.0]);

        await _callMethod(text, 'clear');
        expect(await _callMethod(text, 'getDimensions'), <Object?>[0.0, 0.0]);

        final afterClear = await _callMethod(text, 'add', const <Object?>[
          'ok',
        ]);
        expect(afterClear, 1);
      },
    );

    test(
      'text set and constructor only clear for empty input or a single empty string',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        final constructedWithEmptySpans = await _call(
          runtime,
          const ['love', 'graphics', 'newText'],
          <Object?>[
            font,
            <Object?, Object?>{1: '', 2: ''},
          ],
        );
        expect(
          await _callMethod(constructedWithEmptySpans, 'add', const <Object?>[
            'x',
          ]),
          2,
        );

        final text = await _call(
          runtime,
          const ['love', 'graphics', 'newText'],
          <Object?>[font, 'seed'],
        );

        await _callMethod(text, 'set', <Object?>[
          <Object?, Object?>{1: '', 2: ''},
        ]);
        expect(await _callMethod(text, 'getDimensions'), <Object?>[0.0, 0.0]);
        expect(await _callMethod(text, 'add', const <Object?>['x']), 2);

        await _callMethod(text, 'set', const <Object?>['']);
        expect(await _callMethod(text, 'add', const <Object?>['y']), 1);

        await _callMethod(text, 'setf', <Object?>[
          <Object?, Object?>{1: '', 2: ''},
          12.0,
          'left',
        ]);
        expect(
          await _callMethod(text, 'addf', const <Object?>['z', 12.0, 'left']),
          2,
        );

        await _callMethod(text, 'setf', const <Object?>['', 12.0, 'left']);
        expect(
          await _callMethod(text, 'addf', const <Object?>['w', 12.0, 'left']),
          1,
        );
      },
    );
  });
}

Future<Object?> _call(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
}

Future<Object?> _callMethod(
  Object? receiver,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(
    _rawMethod(receiver, method).call(<Object?>[receiver, ...args]),
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

BuiltinFunction _rawMethod(Object? receiver, String method) {
  final table = receiver is Value ? receiver.raw : receiver;
  expect(table, isA<Map>());
  final entry = (table! as Map)[method];
  return switch (entry) {
    final Value wrapped when wrapped.raw is BuiltinFunction =>
      wrapped.raw as BuiltinFunction,
    final BuiltinFunction function => function,
    _ => throw TestFailure('Expected $method to be a callable Lua method'),
  };
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(
      wrapped.raw as List<Object?>,
      growable: false,
    ).map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
