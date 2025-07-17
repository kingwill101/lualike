import 'dart:convert';
import 'dart:typed_data';

import 'package:lualike/testing.dart';

void main() {
  test(
    'dart.string.bytes.toBytes and dart.string.bytes.fromBytes roundtrip',
    () async {
      final bridge = LuaLike();
      await bridge.execute('''
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
      bridge.execute('''
        dart.string.bytes.fromBytes("not a Uint8List")
      '''),
      throwsA(isA<LuaError>()),
    );
  });

  test('dart.string.bytes.toBytes with empty string', () async {
    final bridge = LuaLike();
    await bridge.execute('''
      bytes_result = dart.string.bytes.toBytes("")
    ''');
    final bytesResult = bridge.getGlobal('bytes_result')!;
    expect(bytesResult.raw, isA<Uint8List>());
    expect(bytesResult.raw, equals(Uint8List.fromList([])));
  });

  test('dart.string.bytes.toBytes with unicode characters', () async {
    final bridge = LuaLike();
    await bridge.execute('''
      -- Construct UTF-8 string for "你好" using proper byte sequence
      local utf8_string = string.char(228, 189, 160, 229, 165, 189)
      local bytes = dart.string.bytes.toBytes(utf8_string)
      str_result = dart.string.bytes.fromBytes(bytes)
    ''');
    final strResult = bridge.getGlobal('str_result')!;
    // The result should be the UTF-8 bytes for "你好"
    final expectedBytes = [228, 189, 160, 229, 165, 189];
    List<int> actualBytes;
    if (strResult.raw is LuaString) {
      actualBytes = (strResult.raw as LuaString).bytes;
    } else {
      // If it's a regular string, convert to bytes
      actualBytes = utf8.encode(strResult.raw.toString());
    }
    expect(actualBytes, equals(expectedBytes));
  });

  test('dart.string.bytes.toBytes throws error with no arguments', () {
    final bridge = LuaLike();
    expectLater(
      bridge.execute('dart.string.bytes.toBytes()'),
      throwsA(isA<LuaError>()),
    );
  });

  test('dart.string.bytes.fromBytes throws error with no arguments', () {
    final bridge = LuaLike();
    expectLater(
      bridge.execute('dart.string.bytes.fromBytes()'),
      throwsA(isA<LuaError>()),
    );
  });

  test('dart.string.bytes.fromBytes with a table of integers', () async {
    final bridge = LuaLike();
    await bridge.execute('''
      local bytes = {104, 101, 108, 108, 111}
      str_result = dart.string.bytes.fromBytes(bytes)
    ''');
    final strResult = bridge.getGlobal('str_result')!;
    expect(strResult.raw, 'hello');
  });
}
