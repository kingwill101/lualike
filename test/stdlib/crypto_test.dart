import 'package:lualike/src/testing/testing.dart';

void main() {
  group('crypto', () {
    test('md5 calculates correct hash', () async {
      final bridge = LuaLikeBridge();
      await bridge.runCode(r'''
        hash = crypto.md5("hello lualike")
      ''');
      final hash = bridge.getGlobal('hash')!;
      expect(hash.raw, '88968dbd4137770ea3dbe0a75cb67e3f');
    });

    test('sha1 calculates correct hash', () async {
      final bridge = LuaLikeBridge();
      await bridge.runCode(r'''
        hash = crypto.sha1("hello lualike")
      ''');
      final hash = bridge.getGlobal('hash')!;
      expect(hash.raw, 'd254a326d2c02a1cb690d9cabd88ea9d5134800c');
    });

    test('sha256 calculates correct hash', () async {
      final bridge = LuaLikeBridge();
      await bridge.runCode(r'''
        hash = crypto.sha256("hello lualike")
      ''');
      final hash = bridge.getGlobal('hash')!;
      expect(
        hash.raw,
        '7eb8d84661263e25fc8dad4a3ac66562437e9473646b95f272fb36ac2cc4f4b5',
      );
    });

    test('sha512 calculates correct hash', () async {
      final bridge = LuaLikeBridge();
      await bridge.runCode(r'''
        hash = crypto.sha512("hello lualike")
      ''');
      final hash = bridge.getGlobal('hash')!;
      expect(
        hash.raw,
        'a99afa91ce6fe84c2ea62999e5e39640ea6021766e9806687ae107522c61d69e38482d2873fc03d48c638a3232fa085b927d29b07c0d2831a645afaae1ffeb11',
      );
    });

    test('hash function works with bytes from dart.string.bytes', () async {
      final bridge = LuaLikeBridge();
      await bridge.runCode(r'''
        local bytes = dart.string.bytes.toBytes("hello lualike")
        hash = crypto.sha256(bytes)
      ''');
      final hash = bridge.getGlobal('hash')!;
      expect(
        hash.raw,
        '7eb8d84661263e25fc8dad4a3ac66562437e9473646b95f272fb36ac2cc4f4b5',
      );
    });

    test('hmac calculates correct hash', () async {
      final bridge = LuaLikeBridge();
      await bridge.runCode(r'''
        hmac_hash = crypto.hmac("SHA-256", "my-secret-key", "hello lualike")
      ''');
      final hmac = bridge.getGlobal('hmac_hash')!;
      expect(
        hmac.raw,
        '7fb6638cc5f853b7178ae0f2728930ca59f5d0d84f4de2d99750a09d854b9a7e',
      );
    });

    test('aesEncrypt and aesDecrypt roundtrip', () async {
      final bridge = LuaLikeBridge();
      await bridge.runCode(r'''
        local key = crypto.randomBytes(16)
        local iv = crypto.randomBytes(16)
        local plaintext = "this is a super secret message"

        local encrypted = crypto.aesEncrypt(key, iv, plaintext)
        local decrypted_bytes = crypto.aesDecrypt(key, iv, encrypted)

        decrypted_text = dart.string.bytes.fromBytes(decrypted_bytes)
      ''');

      final decrypted = bridge.getGlobal('decrypted_text')!;
      expect(decrypted.raw, "this is a super secret message");
    });
  });
}
