import 'package:lualike/src/testing/testing.dart';

void main() {
  group('convert', () {
    test('jsonEncode and jsonDecode roundtrip', () async {
      final bridge = LuaLike();
      await bridge.runCode(r'''
        json_encoded = convert.jsonEncode({
          name = "lualike",
          awesome = true,
          features = {
            ffi = "awesome",
            interop = "easy"
          },
          versions = {1, 2, 3}
        })
        json_decoded = convert.jsonDecode(json_encoded)
      ''');
      final decoded = bridge.getGlobal('json_decoded')!;
      final rawMap = decoded.raw as Map<dynamic, Value>;
      expect(rawMap['awesome']!.raw, true);
      final features = rawMap['features']!.raw as Map<dynamic, Value>;
      expect(features['ffi']!.raw, 'awesome');
      final versions = rawMap['versions']!.raw as List<Value>;
      expect(versions[1].raw, 2);
    });

    test('base64Encode and base64Decode roundtrip', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local bytes = dart.string.bytes.toBytes("hello lualike")
        base64_encoded = convert.base64Encode(bytes)
        local base64_decoded_bytes = convert.base64Decode(base64_encoded)
        base64_decoded_str = dart.string.bytes.fromBytes(base64_decoded_bytes)
      ''');
      final decoded = bridge.getGlobal('base64_decoded_str')!;
      expect(decoded.raw, 'hello lualike');
    });

    test('base64UrlEncode works', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local bytes = dart.string.bytes.toBytes("??lualike??")
        base64url_encoded = convert.base64UrlEncode(bytes)
      ''');
      final encoded = bridge.getGlobal('base64url_encoded')!;
      expect(encoded.raw, 'Pz9sdWFsaWtlPz8=');
    });

    test('asciiEncode and asciiDecode roundtrip', () async {
      final bridge = LuaLike();
      await bridge.runCode(r'''
        ascii_encoded = convert.asciiEncode("hello lualike")
        ascii_decoded = convert.asciiDecode(ascii_encoded)
      ''');
      final decoded = bridge.getGlobal('ascii_decoded')!;
      expect(decoded.raw, 'hello lualike');
    });

    test('latin1Encode and latin1Decode roundtrip', () async {
      final bridge = LuaLike();
      await bridge.runCode(r'''
        latin1_encoded = convert.latin1Encode("blåbærgrød")
        latin1_decoded = convert.latin1Decode(latin1_encoded)
      ''');
      final decoded = bridge.getGlobal('latin1_decoded')!;
      expect(decoded.raw, 'blåbærgrød');
    });
  });
}
