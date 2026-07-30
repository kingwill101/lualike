import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('LOVE graphics shader error transform parity', () {
    test('_transformGLSLErrorMessages rewrites known driver formats', () async {
      final lualike = LuaLike();
      final runtime = lualike.vm;
      installLove2d(runtime: runtime, host: LoveHeadlessHost());
      final transform =
          await lualike.execute('return love.graphics._transformGLSLErrorMessages')
              as Value;

      expect(
        await transform.call(<Object?>[
          'Cannot compile pixel shader code:\n0(7) : error C0000: syntax error',
        ]),
        'Cannot compile pixel shader code:\nLine 7: error: syntax error',
      );

      expect(
        await transform.call(<Object?>[
          'Error validating vertex shader\nERROR: 0:12: error(#132) Syntax error: "foo"',
        ]),
        'Error validating vertex shader code:\n'
        'Line 12: error: Syntax error: "foo"',
      );

      expect(
        await transform.call(<Object?>[
          'Error validating pixel shader\nERROR: 0:5: use of undeclared identifier bar',
        ]),
        'Error validating pixel shader code:\n'
        'Line 5: ERROR: use of undeclared identifier bar',
      );
    });

    test('_transformGLSLErrorMessages passes through unknown messages', () async {
      final lualike = LuaLike();
      final runtime = lualike.vm;
      installLove2d(runtime: runtime, host: LoveHeadlessHost());
      final transform =
          await lualike.execute('return love.graphics._transformGLSLErrorMessages')
              as Value;

      expect(
        await transform.call(<Object?>['unstructured compiler output']),
        'unstructured compiler output',
      );
    });
  });
}
