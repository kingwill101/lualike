import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('LOVE image source parity', () {
    test(
      'newCubeFaces and clone methods mirror upstream source-backed image APIs',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final packed = await luaCallList(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[6, 8],
        );
        await _fillCrossCubemap(packed!);

        final faces = await luaCallList(
          runtime,
          const ['love', 'image', 'newCubeFaces'],
          <Object?>[packed],
        );
        expect(faces, isA<List<Object?>>());
        final faceList = faces! as List<Object?>;
        expect(faceList, hasLength(6));

        const expectedColors = <List<double>>[
          <double>[1.0, 0.0, 0.0, 1.0],
          <double>[0.0, 1.0, 0.0, 1.0],
          <double>[0.0, 0.0, 1.0, 1.0],
          <double>[1.0, 1.0, 0.0, 1.0],
          <double>[1.0, 0.0, 1.0, 1.0],
          <double>[0.0, 1.0, 1.0, 1.0],
        ];
        for (var index = 0; index < expectedColors.length; index++) {
          expect(
            await luaCallMethodList(
              faceList[index]!,
              'getPixel',
              const <Object?>[0, 0],
            ),
            expectedColors[index],
          );
        }

        final clonedImageData = await luaCallMethodList(
          faceList.first!,
          'clone',
        );
        await luaCallMethodList(clonedImageData!, 'setPixel', const <Object?>[
          0,
          0,
          0.25,
          0.5,
          0.75,
          1.0,
        ]);
        expect(
          await luaCallMethodList(faceList.first!, 'getPixel', const <Object?>[
            0,
            0,
          ]),
          expectedColors.first,
        );
        expect(
          await luaCallMethodList(clonedImageData, 'getPixel', const <Object?>[
            0,
            0,
          ]),
          const <double>[0.25, 0.5, 0.75, 1.0],
        );

        final fileData = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_ddsBytes(width: 4, height: 4), 'sample.dds'],
        );
        final compressed = await luaCallList(
          runtime,
          const ['love', 'image', 'newCompressedData'],
          <Object?>[fileData],
        );
        expect(
          await luaCallMethodList(compressed!, 'type'),
          'CompressedImageData',
        );
        expect(
          await luaCallMethodList(compressed, 'typeOf', const <Object?>[
            'Data',
          ]),
          isTrue,
        );
        final compressedClone = await luaCallMethodList(compressed, 'clone');
        expect(
          await luaCallMethodList(compressedClone!, 'type'),
          'CompressedImageData',
        );
        expect(
          await luaCallMethodList(compressedClone, 'getDimensions'),
          <Object?>[4, 4],
        );
        expect(await luaCallMethodList(compressedClone, 'getFormat'), 'DXT1');
      },
    );
  });
}

Future<void> _fillCrossCubemap(Object imageData) async {
  Future<void> fillFace(int ox, int oy, double r, double g, double b) async {
    for (var y = oy; y < oy + 2; y++) {
      for (var x = ox; x < ox + 2; x++) {
        await luaCallMethodList(imageData, 'setPixel', <Object?>[
          x,
          y,
          r,
          g,
          b,
          1.0,
        ]);
      }
    }
  }

  await fillFace(2, 2, 1.0, 0.0, 0.0);
  await fillFace(2, 6, 0.0, 1.0, 0.0);
  await fillFace(2, 0, 0.0, 0.0, 1.0);
  await fillFace(2, 4, 1.0, 1.0, 0.0);
  await fillFace(0, 2, 1.0, 0.0, 1.0);
  await fillFace(4, 2, 0.0, 1.0, 1.0);
}

Uint8List _ddsBytes({required int width, required int height}) {
  const blockBytes = <int>[0, 0, 0, 0, 0, 0, 0, 0];
  final bytes = Uint8List(128 + blockBytes.length);
  bytes.setAll(0, const <int>[0x44, 0x44, 0x53, 0x20]);
  _writeUint32Le(bytes, 4, 124);
  _writeUint32Le(bytes, 12, height);
  _writeUint32Le(bytes, 16, width);
  _writeUint32Le(bytes, 20, blockBytes.length);
  _writeUint32Le(bytes, 28, 1);
  _writeUint32Le(bytes, 76, 32);
  _writeUint32Le(bytes, 80, 0x000004);
  _writeUint32Le(bytes, 84, _fourCc('DXT1'));
  bytes.setAll(128, blockBytes);
  return bytes;
}

int _fourCc(String value) {
  return value.codeUnitAt(0) |
      (value.codeUnitAt(1) << 8) |
      (value.codeUnitAt(2) << 16) |
      (value.codeUnitAt(3) << 24);
}

void _writeUint32Le(Uint8List bytes, int offset, int value) {
  final data = ByteData.sublistView(bytes);
  data.setUint32(offset, value, Endian.little);
}
