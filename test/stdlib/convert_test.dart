import 'package:lualike/testing.dart';

void main() {
  group('convert', () {
    test('jsonEncode and jsonDecode roundtrip', () async {
      final bridge = LuaLike();
      await bridge.execute(r'''
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
      await bridge.execute('''
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
      await bridge.execute('''
        local bytes = dart.string.bytes.toBytes("??lualike??")
        base64url_encoded = convert.base64UrlEncode(bytes)
      ''');
      final encoded = bridge.getGlobal('base64url_encoded')!;
      expect(encoded.raw, 'Pz9sdWFsaWtlPz8=');
    });

    test('asciiEncode and asciiDecode roundtrip', () async {
      final bridge = LuaLike();
      await bridge.execute(r'''
        ascii_encoded = convert.asciiEncode("hello lualike")
        ascii_decoded = convert.asciiDecode(ascii_encoded)
      ''');
      final decoded = bridge.getGlobal('ascii_decoded')!;
      expect(decoded.raw, 'hello lualike');
    });

    test('latin1Encode and latin1Decode roundtrip', () async {
      final bridge = LuaLike();
      await bridge.execute(r'''
        -- Use a string with Latin-1 characters (byte values 128-255)
        -- Create the string using string.char to ensure proper byte values
        local test_str = string.char(98, 108, 229, 98, 230, 114, 103, 114, 246, 100) -- "bl" + å + "b" + æ + "rgr" + ö + "d"
        latin1_encoded = convert.latin1Encode(test_str)
        latin1_decoded = convert.latin1Decode(latin1_encoded)
      ''');
      final decoded = bridge.getGlobal('latin1_decoded')!;
      // The decoded string should match the original byte sequence
      final original = bridge.getGlobal('test_str')!;
      expect(decoded.raw.toString(), equals(original.raw.toString()));
    });
  });
}
