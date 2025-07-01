import 'dart:typed_data';
import 'package:lualike/testing.dart';

void main() {
  test(
    'dart.string.bytes.toBytes and dart.string.bytes.fromBytes roundtrip',
    () async {
      final bridge = LuaLike();
      await bridge.runCode('''
      bytes_result = dart.string.bytes.toBytes("hello")
      str_result = dart.string.bytes.fromBytes(bytes_result)
    ''');
      final strResult = bridge.getGlobal('str_result')!;
      final bytesResult = bridge.getGlobal('bytes_result')!;
      expect(strResult.raw, 'hello');
      expect(bytesResult.raw, isA<Uint8List>());
      expect(
        bytesResult.raw,
        equals(Uint8List.fromList([104, 101, 108, 108, 111])),
      );
    },
  );

  test('dart.string.bytes.fromBytes throws error on invalid input', () {
    final bridge = LuaLike();
    expectLater(
      bridge.runCode('''
        dart.string.bytes.fromBytes("not a Uint8List")
      '''),
      throwsA(isA<LuaError>()),
    );
  });

  test('dart.string.bytes.toBytes with empty string', () async {
    final bridge = LuaLike();
    await bridge.runCode('''
      bytes_result = dart.string.bytes.toBytes("")
    ''');
    final bytesResult = bridge.getGlobal('bytes_result')!;
    expect(bytesResult.raw, isA<Uint8List>());
    expect(bytesResult.raw, equals(Uint8List.fromList([])));
  });

  test('dart.string.bytes.toBytes with unicode characters', () async {
    final bridge = LuaLike();
    await bridge.runCode('''
      local bytes = dart.string.bytes.toBytes("你好")
      str_result = dart.string.bytes.fromBytes(bytes)
    ''');
    final strResult = bridge.getGlobal('str_result')!;
    expect(strResult.raw, '你好');
  });

  test('dart.string.bytes.toBytes throws error with no arguments', () {
    final bridge = LuaLike();
    expectLater(
      bridge.runCode('dart.string.bytes.toBytes()'),
      throwsA(isA<LuaError>()),
    );
  });

  test('dart.string.bytes.fromBytes throws error with no arguments', () {
    final bridge = LuaLike();
    expectLater(
      bridge.runCode('dart.string.bytes.fromBytes()'),
      throwsA(isA<LuaError>()),
    );
  });

  test('dart.string.bytes.fromBytes with a table of integers', () async {
    final bridge = LuaLike();
    await bridge.runCode('''
      local bytes = {104, 101, 108, 108, 111}
      str_result = dart.string.bytes.fromBytes(bytes)
    ''');
    final strResult = bridge.getGlobal('str_result')!;
    expect(strResult.raw, 'hello');
  });
}
