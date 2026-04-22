import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics layered compressed images', () {
    test(
      'newArrayImage accepts CompressedImageData slices and drawLayer records the selected layer',
      () async {
        final runtime = Interpreter();
        final host = LoveHeadlessHost();
        installLove2d(runtime: runtime, host: host);

        final red = await _newCompressedData(
          runtime,
          'red.dds',
          _ddsBytes(width: 16, height: 8),
        );
        final green = await _newCompressedData(
          runtime,
          'green.ktx',
          _ktxBytes(width: 16, height: 8),
        );

        final array = await _call(
          runtime,
          const ['love', 'graphics', 'newArrayImage'],
          <Object?>[
            _luaSeq(<Object?>[red, green]),
            <Object?, Object?>{'dpiscale': 2.0},
          ],
        );

        expect(await _callMethod(array!, 'isCompressed'), isTrue);
        expect(await _callMethod(array, 'isReadable'), isFalse);
        expect(await _callMethod(array, 'getTextureType'), 'array');
        expect(await _callMethod(array, 'getLayerCount'), 2);
        expect(await _callMethod(array, 'getMipmapCount'), 2);
        expect(await _callMethod(array, 'getDimensions'), <Object?>[8, 4]);
        expect(await _callMethod(array, 'getPixelDimensions'), <Object?>[
          16,
          8,
        ]);

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'drawLayer'],
          <Object?>[array, 2, 0, 0],
        );

        expect(host.graphics.commands, hasLength(1));
        final draw = host.graphics.commands.single as LoveImageCommand;
        expect(draw.layer, 1);
        expect(draw.image.textureType, 'array');
        expect(draw.image.compressed, isTrue);
        expect(draw.image.sliceImages, hasLength(2));
        expect(draw.image.sliceImages![0].compressed, isTrue);
        expect(draw.image.sliceImages![1].compressed, isTrue);
        expect(draw.image.sliceImages![0].format, 'DXT1');
        expect(draw.image.sliceImages![1].format, 'DXT1');
      },
    );

    test(
      'newVolumeImage and newCubeImage accept CompressedImageData sources and preserve metadata',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final ddsA = await _newCompressedData(
          runtime,
          'a.dds',
          _ddsBytes(width: 16, height: 8),
        );
        final ddsB = await _newCompressedData(
          runtime,
          'b.dds',
          _ddsBytes(width: 16, height: 8),
        );
        final ktx = await _newCompressedData(
          runtime,
          'c.ktx',
          _ktxBytes(width: 16, height: 8),
        );
        final cubeDds = await _newCompressedData(
          runtime,
          'cube.dds',
          _ddsBytes(width: 16, height: 16),
        );
        final cubeKtx = await _newCompressedData(
          runtime,
          'cube.ktx',
          _ktxBytes(width: 16, height: 16),
        );

        final volume = await _call(
          runtime,
          const ['love', 'graphics', 'newVolumeImage'],
          <Object?>[
            _luaSeq(<Object?>[ddsA, ddsB, ktx]),
            <Object?, Object?>{'dpiscale': 2.0},
          ],
        );
        final cube = await _call(
          runtime,
          const ['love', 'graphics', 'newCubeImage'],
          <Object?>[
            _luaSeq(<Object?>[
              cubeDds,
              cubeKtx,
              cubeDds,
              cubeKtx,
              cubeDds,
              cubeKtx,
            ]),
          ],
        );

        expect(await _callMethod(volume!, 'isCompressed'), isTrue);
        expect(await _callMethod(volume, 'isReadable'), isFalse);
        expect(await _callMethod(volume, 'getTextureType'), 'volume');
        expect(await _callMethod(volume, 'getLayerCount'), 1);
        expect(await _callMethod(volume, 'getDepth'), 3);
        expect(await _callMethod(volume, 'getMipmapCount'), 2);
        expect(await _callMethod(volume, 'getDimensions'), <Object?>[8, 4]);

        expect(await _callMethod(cube!, 'isCompressed'), isTrue);
        expect(await _callMethod(cube, 'isReadable'), isFalse);
        expect(await _callMethod(cube, 'getTextureType'), 'cube');
        expect(await _callMethod(cube, 'getLayerCount'), 6);
        expect(await _callMethod(cube, 'getDepth'), 1);
        expect(await _callMethod(cube, 'getMipmapCount'), 2);
        expect(await _callMethod(cube, 'getDimensions'), <Object?>[16, 16]);

        final wrappedVolume = arrayLikeImage(volume);
        final wrappedCube = arrayLikeImage(cube);
        expect(wrappedVolume.sliceImages, hasLength(3));
        expect(wrappedCube.sliceImages, hasLength(6));
        expect(
          wrappedVolume.sliceImages!.every((slice) => slice.compressed),
          isTrue,
        );
        expect(
          wrappedCube.sliceImages!.every((slice) => slice.compressed),
          isTrue,
        );
      },
    );
  });
}

LoveImage arrayLikeImage(Object? wrapped) =>
    (wrapped! as Map<dynamic, dynamic>)['__love2d_image__'] as LoveImage;

Future<Object?> _newCompressedData(
  Interpreter runtime,
  String filename,
  Uint8List bytes,
) async {
  final fileData = await _call(
    runtime,
    const ['love', 'filesystem', 'newFileData'],
    <Object?>[bytes, filename],
  );
  return _call(
    runtime,
    const ['love', 'image', 'newCompressedData'],
    <Object?>[fileData],
  );
}

Uint8List _ddsBytes({required int width, required int height}) {
  final mip0Size = ((width + 3) ~/ 4) * ((height + 3) ~/ 4) * 8;
  final mip1Size = (((width >> 1) + 3) ~/ 4) * (((height >> 1) + 3) ~/ 4) * 8;
  final bytes = Uint8List(128 + mip0Size + mip1Size);
  bytes.setAll(0, const <int>[0x44, 0x44, 0x53, 0x20]);
  _writeUint32Le(bytes, 4, 124);
  _writeUint32Le(bytes, 12, height);
  _writeUint32Le(bytes, 16, width);
  _writeUint32Le(bytes, 20, mip0Size);
  _writeUint32Le(bytes, 28, 2);
  _writeUint32Le(bytes, 76, 32);
  _writeUint32Le(bytes, 80, 0x000004);
  _writeUint32Le(bytes, 84, _fourCc('DXT1'));
  return bytes;
}

Uint8List _ktxBytes({required int width, required int height}) {
  final mip0Size = ((width + 3) ~/ 4) * ((height + 3) ~/ 4) * 8;
  final mip1Width = width > 1 ? width >> 1 : 1;
  final mip1Height = height > 1 ? height >> 1 : 1;
  final mip1Size = ((mip1Width + 3) ~/ 4) * ((mip1Height + 3) ~/ 4) * 8;
  final bytes = Uint8List(64 + 4 + mip0Size + 4 + mip1Size);
  bytes.setAll(0, const <int>[
    0xAB,
    0x4B,
    0x54,
    0x58,
    0x20,
    0x31,
    0x31,
    0xBB,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x01,
    0x02,
    0x03,
    0x04,
  ]);
  _writeUint32Le(bytes, 16, 0);
  _writeUint32Le(bytes, 20, 1);
  _writeUint32Le(bytes, 24, 0);
  _writeUint32Le(bytes, 28, 0x83F0);
  _writeUint32Le(bytes, 32, 0x1907);
  _writeUint32Le(bytes, 36, width);
  _writeUint32Le(bytes, 40, height);
  _writeUint32Le(bytes, 44, 0);
  _writeUint32Le(bytes, 48, 0);
  _writeUint32Le(bytes, 52, 1);
  _writeUint32Le(bytes, 56, 2);
  _writeUint32Le(bytes, 60, 0);
  _writeUint32Le(bytes, 64, mip0Size);
  _writeUint32Le(bytes, 68 + mip0Size, mip1Size);
  return bytes;
}

void _writeUint32Le(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
  bytes[offset + 2] = (value >> 16) & 0xFF;
  bytes[offset + 3] = (value >> 24) & 0xFF;
}

int _fourCc(String value) {
  return value.codeUnitAt(0) |
      (value.codeUnitAt(1) << 8) |
      (value.codeUnitAt(2) << 16) |
      (value.codeUnitAt(3) << 24);
}

Map<Object?, Object?> _luaSeq(List<Object?> values) {
  return <Object?, Object?>{
    for (var index = 0; index < values.length; index++)
      index + 1: values[index],
  };
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
