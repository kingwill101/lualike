import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.data lz4 bindings', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime);
    });

    test(
      'compresses to LOVE-style LZ4 blocks and roundtrips through object and string containers',
      () async {
        final compressed = await luaCallList(
          runtime,
          const ['love', 'data', 'compress'],
          const <Object?>['data', 'lz4', 'hello'],
        );
        expect(await luaCallMethodList(compressed, 'type'), 'CompressedData');
        expect(await luaCallMethodList(compressed, 'getFormat'), 'lz4');
        expect(
          await luaCallMethodList(compressed, 'typeOf', const <Object?>[
            'Data',
          ]),
          isTrue,
        );
        expect(
          await luaCallList(
            runtime,
            const ['love', 'data', 'decompress'],
            <Object?>['string', compressed],
          ),
          'hello',
        );

        final rawCompressed = await luaCallRaw(
          runtime,
          const ['love', 'data', 'compress'],
          const <Object?>['string', 'lz4', 'hello'],
        );
        expect(
          await luaCallList(
            runtime,
            const ['love', 'data', 'encode'],
            <Object?>['string', 'hex', rawCompressed],
          ),
          '050000005068656c6c6f',
        );
      },
    );

    test('encodes extended literal lengths in LOVE LZ4 output', () async {
      const payload = 'abcdefghijklmnopqrst';
      final rawCompressed = await luaCallRaw(
        runtime,
        const ['love', 'data', 'compress'],
        const <Object?>['string', 'lz4', payload],
      );
      expect(
        await luaCallList(
          runtime,
          const ['love', 'data', 'encode'],
          <Object?>['string', 'hex', rawCompressed],
        ),
        '14000000f0056162636465666768696a6b6c6d6e6f7071727374',
      );
      expect(
        await luaCallList(
          runtime,
          const ['love', 'data', 'decompress'],
          <Object?>['string', 'lz4', rawCompressed],
        ),
        payload,
      );
    });

    test(
      'decompresses LOVE-style LZ4 match sequences from raw bytes',
      () async {
        final encoded = await luaCallList(
          runtime,
          const ['love', 'data', 'decode'],
          const <Object?>['data', 'hex', '0a000000326162630300107a'],
        );
        expect(
          await luaCallList(
            runtime,
            const ['love', 'data', 'decompress'],
            <Object?>['string', 'lz4', encoded],
          ),
          'abcabcabcz',
        );
      },
    );

    test('reports invalid lz4 payloads as Lua errors', () async {
      final invalid = await luaCallList(
        runtime,
        const ['love', 'data', 'decode'],
        const <Object?>['data', 'hex', '04000000000000'],
      );
      expect(
        luaCallList(
          runtime,
          const ['love', 'data', 'decompress'],
          <Object?>['string', 'lz4', invalid],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Could not decompress LZ4-compressed data.'),
          ),
        ),
      );
    });
  });
}
