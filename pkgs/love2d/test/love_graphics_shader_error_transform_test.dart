import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('LOVE graphics shader error transform parity', () {
    test('_transformGLSLErrorMessages rewrites known driver formats', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      expect(
        await luaCallList(
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
        await luaCallList(
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
        await luaCallList(
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
          await luaCallList(
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
