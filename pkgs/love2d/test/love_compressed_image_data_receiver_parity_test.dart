import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.image compressed image receiver parity', () {
    test(
      'CompressedImageData type metadata survives release while other methods fail',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final fileData = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_ddsBytes(), 'fixture.dds'],
        );
        final compressed = await luaCall(
          runtime,
          const ['love', 'image', 'newCompressedData'],
          <Object?>[fileData],
        );

        final typeMethod = luaRawMethod(compressed, 'type');
        final typeOfMethod = luaRawMethod(compressed, 'typeOf');

        expect(
          await luaResolveCallResult(typeMethod.call(<Object?>[compressed])),
          'CompressedImageData',
        );
        expect(
          await luaResolveCallResult(
            typeOfMethod.call(<Object?>[compressed, 'Data']),
          ),
          isTrue,
        );

        await expectLater(
          () => luaResolveCallResult(typeMethod.call(const <Object?>[])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' "
                  '(CompressedImageData expected, got nil)',
            ),
          ),
        );

        await expectLater(
          () => luaResolveCallResult(
            typeOfMethod.call(const <Object?>['oops', 'Data']),
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'typeOf' "
                  '(CompressedImageData expected, got string)',
            ),
          ),
        );

        expect(await luaCallMethod(compressed, 'release'), isTrue);
        expect(await luaCallMethod(compressed, 'release'), isFalse);

        await expectLater(
          () => luaCallMethod(compressed, 'getWidth'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        expect(await luaCallMethod(compressed, 'type'), 'CompressedImageData');
        expect(
          await luaCallMethod(compressed, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
      },
    );
  });
}

Uint8List _ddsBytes() {
  const blockBytes = <int>[0x00, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
  final bytes = Uint8List(128 + blockBytes.length);
  bytes.setAll(0, const <int>[0x44, 0x44, 0x53, 0x20]);
  _writeUint32Le(bytes, 4, 124);
  _writeUint32Le(bytes, 12, 4);
  _writeUint32Le(bytes, 16, 4);
  _writeUint32Le(bytes, 20, blockBytes.length);
  _writeUint32Le(bytes, 28, 1);
  _writeUint32Le(bytes, 76, 32);
  _writeUint32Le(bytes, 80, 0x000004);
  _writeUint32Le(bytes, 84, _fourCc('DXT1'));
  bytes.setAll(128, blockBytes);
  return bytes;
}

void _writeUint32Le(Uint8List target, int offset, int value) {
  final data = ByteData.sublistView(target);
  data.setUint32(offset, value, Endian.little);
}

int _fourCc(String value) {
  final codeUnits = value.codeUnits;
  return codeUnits[0] |
      (codeUnits[1] << 8) |
      (codeUnits[2] << 16) |
      (codeUnits[3] << 24);
}
