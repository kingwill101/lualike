import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.data bindings', () {
    late LuaRuntime runtime;

    setUp(() {
      runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime);
    });

    test(
      'newByteData supports size, string, and data slicing inputs',
      () async {
        final empty = await luaCallList(
          runtime,
          const ['love', 'data', 'newByteData'],
          const <Object?>[4],
        );
        expect(await luaCallMethodList(empty, 'type'), 'ByteData');
        expect(
          await luaCallMethodList(empty, 'typeOf', const <Object?>['Data']),
          isTrue,
        );
        expect(await luaCallMethodList(empty, 'getSize'), 4);

        final source = await luaCallList(
          runtime,
          const ['love', 'data', 'newByteData'],
          const <Object?>['hello world'],
        );
        expect(await luaCallMethodList(source, 'getString'), 'hello world');

        final slice = await luaCallList(
          runtime,
          const ['love', 'data', 'newByteData'],
          <Object?>[source, 6, 5],
        );
        expect(await luaCallMethodList(slice, 'getString'), 'world');

        final tail = await luaCallList(
          runtime,
          const ['love', 'data', 'newByteData'],
          <Object?>[source, 6],
        );
        expect(await luaCallMethodList(tail, 'getString'), 'world');
      },
    );

    test(
      'newDataView slices existing data and clone preserves view type',
      () async {
        final source = await luaCallList(
          runtime,
          const ['love', 'data', 'newByteData'],
          const <Object?>['abcdef'],
        );

        final view = await luaCallList(
          runtime,
          const ['love', 'data', 'newDataView'],
          <Object?>[source, 1, 3],
        );
        expect(await luaCallMethodList(view, 'type'), 'DataView');
        expect(
          await luaCallMethodList(view, 'typeOf', const <Object?>['Data']),
          isTrue,
        );
        expect(await luaCallMethodList(view, 'getString'), 'bcd');

        final clone = await luaCallMethodList(view, 'clone');
        expect(await luaCallMethodList(clone, 'type'), 'DataView');
        expect(await luaCallMethodList(clone, 'getString'), 'bcd');
      },
    );

    test(
      'encode, decode, and hash support string and data containers',
      () async {
        final fileData = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          const <Object?>['binary payload', 'payload.bin'],
        );

        final copiedFromFileData = await luaCallList(
          runtime,
          const ['love', 'data', 'newByteData'],
          <Object?>[fileData, 7, 7],
        );
        expect(
          await luaCallMethodList(copiedFromFileData, 'getString'),
          'payload',
        );

        expect(
          await luaCallList(
            runtime,
            const ['love', 'data', 'encode'],
            <Object?>['string', 'hex', fileData],
          ),
          '62696e617279207061796c6f6164',
        );

        expect(
          await luaCallList(
            runtime,
            const ['love', 'data', 'encode'],
            const <Object?>['string', 'hex', 'Hi'],
          ),
          '4869',
        );

        final decoded = await luaCallList(
          runtime,
          const ['love', 'data', 'decode'],
          const <Object?>['data', 'hex', '48656c6c6f'],
        );
        expect(await luaCallMethodList(decoded, 'type'), 'ByteData');
        expect(await luaCallMethodList(decoded, 'getString'), 'Hello');

        expect(
          await luaCallList(
            runtime,
            const ['love', 'data', 'encode'],
            const <Object?>['string', 'base64', 'hello', 4],
          ),
          'aGVs\nbG8=',
        );
        expect(
          await luaCallList(
            runtime,
            const ['love', 'data', 'decode'],
            const <Object?>['string', 'base64', 'aGVs\nbG8='],
          ),
          'hello',
        );

        final digest = await luaCallRaw(
          runtime,
          const ['love', 'data', 'hash'],
          const <Object?>['sha256', 'abc'],
        );
        expect(
          await luaCallList(
            runtime,
            const ['love', 'data', 'encode'],
            <Object?>['string', 'hex', digest],
          ),
          'ba7816bf8f01cfea414140de5dae2223'
          'b00361a396177a9cb410ff61f20015ad',
        );
      },
    );

    test('compress and decompress roundtrip zlib, gzip, and deflate', () async {
      final compressed = await luaCallList(
        runtime,
        const ['love', 'data', 'compress'],
        const <Object?>['data', 'zlib', 'hello hello hello'],
      );
      expect(await luaCallMethodList(compressed, 'type'), 'CompressedData');
      expect(await luaCallMethodList(compressed, 'getFormat'), 'zlib');
      expect(
        await luaCallMethodList(compressed, 'typeOf', const <Object?>['Data']),
        isTrue,
      );
      expect(
        await luaCallList(
          runtime,
          const ['love', 'data', 'decompress'],
          <Object?>['string', compressed],
        ),
        'hello hello hello',
      );

      final source = await luaCallList(
        runtime,
        const ['love', 'data', 'newByteData'],
        const <Object?>['payload'],
      );
      final gzipBytes = await luaCallRaw(
        runtime,
        const ['love', 'data', 'compress'],
        <Object?>['string', 'gzip', source],
      );
      expect(
        await luaCallList(
          runtime,
          const ['love', 'data', 'decompress'],
          <Object?>['string', 'gzip', gzipBytes],
        ),
        'payload',
      );

      final deflated = await luaCallRaw(
        runtime,
        const ['love', 'data', 'compress'],
        const <Object?>['string', 'deflate', 'raw bytes'],
      );
      final inflated = await luaCallList(
        runtime,
        const ['love', 'data', 'decompress'],
        <Object?>['data', 'deflate', deflated],
      );
      expect(await luaCallMethodList(inflated, 'getString'), 'raw bytes');
    });

    test(
      'pack, unpack, and getPackedSize delegate to Lua string packing',
      () async {
        expect(
          await luaCallList(
            runtime,
            const ['love', 'data', 'getPackedSize'],
            const <Object?>['<I4'],
          ),
          4,
        );

        final packed = await luaCallList(
          runtime,
          const ['love', 'data', 'pack'],
          const <Object?>['data', '<I4', 0x12345678],
        );
        expect(await luaCallMethodList(packed, 'type'), 'ByteData');
        expect(
          await luaCallList(
            runtime,
            const ['love', 'data', 'encode'],
            <Object?>['string', 'hex', packed],
          ),
          '78563412',
        );

        expect(
          await luaCallList(
            runtime,
            const ['love', 'data', 'unpack'],
            <Object?>['<I4', packed],
          ),
          <Object?>[0x12345678, 5],
        );
      },
    );
  });
}
