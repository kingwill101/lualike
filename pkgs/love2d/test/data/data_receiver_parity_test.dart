import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.data receiver parity', () {
    test(
      'ByteData type metadata survives release while other methods fail',
      () async {
        final lualike = LuaLike();
        final runtime = lualike.vm;
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final typeResult = await lualike.execute('''
local byteData = love.data.newByteData("hello")
return byteData:type(), byteData:typeOf("Data")
''');
        expect(
          (typeResult as List).map((e) => (e as Value).unwrap()).toList(),
          <Object?>['ByteData', true],
        );

        await expectLater(
          lualike.execute('''
local byteData = love.data.newByteData("hello")
return byteData.type()
'''),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' (ByteData expected, got nil)",
            ),
          ),
        );

        await expectLater(
          lualike.execute('''
local byteData = love.data.newByteData("hello")
return byteData.typeOf("oops", "Data")
'''),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'typeOf' (ByteData expected, got string)",
            ),
          ),
        );

        expect(
          ((await lualike.execute('''
local byteData = love.data.newByteData("hello")
return byteData:release()
''')) as Value)
              .unwrap(),
          isTrue,
        );
        expect(
          ((await lualike.execute('''
local byteData = love.data.newByteData("hello")
byteData:release()
return byteData:release()
''')) as Value)
              .unwrap(),
          isFalse,
        );

        await expectLater(
          lualike.execute('''
local byteData = love.data.newByteData("hello")
byteData:release()
return byteData:getString()
'''),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        final releasedTypeResult = await lualike.execute('''
local byteData = love.data.newByteData("hello")
byteData:release()
return byteData:type(), byteData:typeOf("Object")
''');
        expect(
          (releasedTypeResult as List)
              .map((e) => (e as Value).unwrap())
              .toList(),
          <Object?>['ByteData', true],
        );
      },
    );

    test(
      'FileData type metadata survives release while data methods fail',
      () async {
        final lualike = LuaLike();
        final runtime = lualike.vm;
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final typeResult = await lualike.execute('''
local fileData = love.filesystem.newFileData("payload", "payload.bin")
return fileData:type(), fileData:typeOf("Data")
''');
        expect(
          (typeResult as List).map((e) => (e as Value).unwrap()).toList(),
          <Object?>['FileData', true],
        );

        await expectLater(
          lualike.execute('''
local fileData = love.filesystem.newFileData("payload", "payload.bin")
return fileData.type()
'''),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' (FileData expected, got nil)",
            ),
          ),
        );

        await expectLater(
          lualike.execute('''
local fileData = love.filesystem.newFileData("payload", "payload.bin")
return fileData.typeOf("oops", "Data")
'''),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'typeOf' (FileData expected, got string)",
            ),
          ),
        );

        expect(
          ((await lualike.execute('''
local fileData = love.filesystem.newFileData("payload", "payload.bin")
return fileData:release()
''')) as Value)
              .unwrap(),
          isTrue,
        );
        expect(
          ((await lualike.execute('''
local fileData = love.filesystem.newFileData("payload", "payload.bin")
fileData:release()
return fileData:release()
''')) as Value)
              .unwrap(),
          isFalse,
        );

        await expectLater(
          lualike.execute('''
local fileData = love.filesystem.newFileData("payload", "payload.bin")
fileData:release()
return fileData:getString()
'''),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        final releasedTypeResult = await lualike.execute('''
local fileData = love.filesystem.newFileData("payload", "payload.bin")
fileData:release()
return fileData:type(), fileData:typeOf("Object")
''');
        expect(
          (releasedTypeResult as List)
              .map((e) => (e as Value).unwrap())
              .toList(),
          <Object?>['FileData', true],
        );
      },
    );
  });
}
