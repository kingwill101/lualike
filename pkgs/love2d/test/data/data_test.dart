import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.data bindings', () {
    late LuaRuntime runtime;
    late LuaLike lualike;

    setUp(() {
      lualike = LuaLike();
      runtime = lualike.vm;
      installLove2d(runtime: runtime);
    });

    test(
      'newByteData supports size, string, and data slicing inputs',
      () async {
        expect(
          ((await lualike.execute('''
local empty = love.data.newByteData(4)
return empty:type()
''')) as Value)
              .unwrap(),
          'ByteData',
        );
        expect(
          ((await lualike.execute('''
local empty = love.data.newByteData(4)
return empty:typeOf("Data")
''')) as Value)
              .unwrap(),
          isTrue,
        );
        expect(
          ((await lualike.execute('''
local empty = love.data.newByteData(4)
return empty:getSize()
''')) as Value)
              .unwrap(),
          4,
        );

        expect(
          ((await lualike.execute('''
local source = love.data.newByteData("hello world")
return source:getString()
''')) as Value)
              .unwrap(),
          'hello world',
        );

        expect(
          ((await lualike.execute('''
local source = love.data.newByteData("hello world")
local slice = love.data.newByteData(source, 6, 5)
return slice:getString()
''')) as Value)
              .unwrap(),
          'world',
        );

        expect(
          ((await lualike.execute('''
local source = love.data.newByteData("hello world")
local tail = love.data.newByteData(source, 6)
return tail:getString()
''')) as Value)
              .unwrap(),
          'world',
        );
      },
    );

    test(
      'newDataView slices existing data and clone preserves view type',
      () async {
        final viewResult = await lualike.execute('''
local source = love.data.newByteData("abcdef")
local view = love.data.newDataView(source, 1, 3)
return view:type(), view:typeOf("Data"), view:getString()
''');
        expect(
          (viewResult as List)
              .map((e) => (e as Value).unwrap())
              .toList(),
          <Object?>['DataView', true, 'bcd'],
        );

        final cloneResult = await lualike.execute('''
local source = love.data.newByteData("abcdef")
local view = love.data.newDataView(source, 1, 3)
local clone = view:clone()
return clone:type(), clone:getString()
''');
        expect(
          (cloneResult as List)
              .map((e) => (e as Value).unwrap())
              .toList(),
          <Object?>['DataView', 'bcd'],
        );
      },
    );

    test(
      'encode, decode, and hash support string and data containers',
      () async {
        expect(
          ((await lualike.execute('''
local fileData = love.filesystem.newFileData("binary payload", "payload.bin")
return love.data.newByteData(fileData, 7, 7):getString()
''')) as Value)
              .unwrap(),
          'payload',
        );

        expect(
          ((await lualike.execute('''
local fileData = love.filesystem.newFileData("binary payload", "payload.bin")
return love.data.encode("string", "hex", fileData)
''')) as Value)
              .unwrap(),
          '62696e617279207061796c6f6164',
        );

        expect(
          ((await lualike.execute('''
return love.data.encode("string", "hex", "Hi")
''')) as Value)
              .unwrap(),
          '4869',
        );

        final decodedResult = await lualike.execute('''
local decoded = love.data.decode("data", "hex", "48656c6c6f")
return decoded:type(), decoded:getString()
''');
        expect(
          (decodedResult as List)
              .map((e) => (e as Value).unwrap())
              .toList(),
          <Object?>['ByteData', 'Hello'],
        );

        expect(
          ((await lualike.execute('''
return love.data.encode("string", "base64", "hello")
''')) as Value)
              .unwrap(),
          'aGVsbG8=',
        );
        expect(
          ((await lualike.execute('''
return love.data.decode("string", "base64", "aGVsbG8=")
''')) as Value)
              .unwrap(),
          'hello',
        );

        expect(
          ((await lualike.execute('''
return love.data.encode("string", "hex", love.data.hash("sha256", "abc"))
''')) as Value)
              .unwrap(),
          'ba7816bf8f01cfea414140de5dae2223'
          'b00361a396177a9cb410ff61f20015ad',
        );
      },
    );

    test('compress and decompress roundtrip zlib, gzip, and deflate', () async {
      final compressedResult = await lualike.execute('''
local compressed = love.data.compress("data", "zlib", "hello hello hello")
return compressed:type(), compressed:typeOf("Data")
''');
      expect(
        (compressedResult as List)
            .map((e) => (e as Value).unwrap())
            .toList(),
        <Object?>['CompressedData', true],
      );
      expect(
        ((await lualike.execute('''
local compressed = love.data.compress("data", "zlib", "hello hello hello")
return love.data.decompress("string", compressed)
''')) as Value)
            .unwrap(),
        'hello hello hello',
      );

      expect(
        ((await lualike.execute('''
local source = love.data.newByteData("payload")
local gzipBytes = love.data.compress("string", "gzip", source)
return love.data.decompress("string", "gzip", gzipBytes)
''')) as Value)
            .unwrap(),
        'payload',
      );

      expect(
        ((await lualike.execute('''
local deflated = love.data.compress("string", "deflate", "raw bytes")
local inflated = love.data.decompress("data", "deflate", deflated)
return inflated:getString()
''')) as Value)
            .unwrap(),
        'raw bytes',
      );
    });

    test(
      'pack, unpack, and getPackedSize delegate to Lua string packing',
      () async {
        expect(
          ((await lualike.execute('return love.data.getPackedSize("<I4")'))
                  as Value)
              .unwrap(),
          4,
        );

        final packedResult = await lualike.execute('''
local packed = love.data.pack("data", "<I4", 0x12345678)
return packed:type(), love.data.encode("string", "hex", packed)
''');
        expect(
          (packedResult as List)
              .map((e) => (e as Value).unwrap())
              .toList(),
          <Object?>['ByteData', '78563412'],
        );

        final unpackedResult = await lualike.execute('''
local packed = love.data.pack("data", "<I4", 0x12345678)
return love.data.unpack("<I4", packed)
''');
        expect(
          (unpackedResult as List)
              .map((e) => (e as Value).unwrap())
              .toList(),
          <Object?>[0x12345678, 5],
        );
      },
    );
  });
}
