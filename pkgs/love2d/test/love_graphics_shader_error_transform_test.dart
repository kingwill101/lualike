import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('LOVE graphics shader error transform parity', () {
    test('_transformGLSLErrorMessages rewrites known driver formats', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      expect(
        await _call(
          runtime,
          const ['love', 'graphics', '_transformGLSLErrorMessages'],
          const <Object?>[
            'Cannot compile pixel shader code:\n'
                '0(7) : error C0000: syntax error',
          ],
        ),
        'Cannot compile pixel shader code:\nLine 7: error: syntax error',
      );

      expect(
        await _call(
          runtime,
          const ['love', 'graphics', '_transformGLSLErrorMessages'],
          const <Object?>[
            'Error validating vertex shader\n'
                'ERROR: 0:12: error(#132) Syntax error: "foo"',
          ],
        ),
        'Error validating vertex shader code:\n'
        'Line 12: error: Syntax error: "foo"',
      );

      expect(
        await _call(
          runtime,
          const ['love', 'graphics', '_transformGLSLErrorMessages'],
          const <Object?>[
            'Error validating pixel shader\n'
                'ERROR: 0:5: use of undeclared identifier bar',
          ],
        ),
        'Error validating pixel shader code:\n'
        'Line 5: ERROR: use of undeclared identifier bar',
      );
    });

    test(
      '_transformGLSLErrorMessages passes through unknown messages',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        expect(
          await _call(
            runtime,
            const ['love', 'graphics', '_transformGLSLErrorMessages'],
            const <Object?>['unstructured compiler output'],
          ),
          'unstructured compiler output',
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
  if (resolved is List<Object?>) {
    return resolved.map(_unwrap).toList(growable: false);
  }
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(
      wrapped.raw as List<Object?>,
      growable: false,
    ).map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
