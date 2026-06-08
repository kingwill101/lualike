import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:convert/convert.dart' show hex;
import 'package:lualike/src/builtin_function.dart';

import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/stdlib/doc.dart';
import 'library.dart';

/// Crypto library implementation using the new Library system
class CryptoLibrary extends Library {
  @override
  String get name => "crypto";

  @override
  String get description => 'Cryptographic hash functions (MD5, SHA1, SHA256).';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    // Register all crypto functions directly
    context.define('md5', _HashFunction(md5, interpreter!));
    context.define('sha1', _HashFunction(sha1, interpreter!));
    context.define('sha256', _HashFunction(sha256, interpreter!));
    context.define('sha512', _HashFunction(sha512, interpreter!));
    context.define('hmac', HmacFunction(interpreter!));
    context.define('randomBytes', RandomBytesFunction(interpreter!));
    context.define('aesEncrypt', _AesCbcFunction(true, interpreter!));
    context.define('aesDecrypt', _AesCbcFunction(false, interpreter!));
  }
}

Uint8List _toBytes(Object? value) {
  final raw = rawLuaSlot(value);
  if (raw is String) {
    return utf8.encode(raw);
  }
  if (raw is LuaString) {
    // Preserve the original byte representation when passed a LuaString.
    return Uint8List.fromList(raw.bytes);
  }
  if (raw is Uint8List) {
    return raw;
  }
  if (raw is List) {
    try {
      return Uint8List.fromList(raw.cast<int>());
    } catch (e) {
      throw LuaError('Expected a List of integers');
    }
  }
  throw LuaError('Expected a string, Uint8List, or a table of integers');
}

class _HashFunction extends BuiltinFunction {
  final Hash _hash;

  _HashFunction(this._hash, super.interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Computes a cryptographic hash of a string.',
    params: [
      DocParam(
        'algorithm',
        'string',
        'Hash algorithm: "md5", "sha1", "sha256".',
      ),
      DocParam('input', 'string', 'The input string to hash.'),
    ],
    returns: 'The hex-encoded hash string.',
    category: 'crypto',
    example: 'crypto.hash("sha256", "hello")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('hash function requires 1 argument');
    }
    final input = _toBytes(args[0]);
    final digest = _hash.convert(input);
    return dartStringValue(digest.toString());
  }
}

class HmacFunction extends BuiltinFunction {
  HmacFunction(super.interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Computes an HMAC for a message using a secret key.',
    params: [
      DocParam(
        'algorithm',
        'string',
        'Hash algorithm: "md5", "sha1", "sha256".',
      ),
      DocParam('key', 'string', 'The secret key.'),
      DocParam('message', 'string', 'The message to authenticate.'),
    ],
    returns: 'The hex-encoded HMAC string.',
    category: 'crypto',
    example: 'crypto.hmac("sha256", "key", "message")',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 3) {
      throw LuaError(
        'hmac requires 3 arguments: digest name, key, and message',
      );
    }

    final digestName = rawLuaSlot(args[0]).toString();
    final key = _toBytes(args[1]);
    final message = _toBytes(args[2]);

    try {
      final hmac = pc.Mac('$digestName/HMAC');
      hmac.init(pc.KeyParameter(key));
      final result = hmac.process(message);
      return dartStringValue(hex.encode(result));
    } catch (e) {
      throw LuaError('Failed to compute HMAC: $e');
    }
  }
}

class RandomBytesFunction extends BuiltinFunction {
  RandomBytesFunction(super.interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Generates cryptographically secure random bytes.',
    params: [
      DocParam('count', 'number', 'Number of random bytes to generate.'),
    ],
    returns: 'A random byte string.',
    category: 'crypto',
    example: 'local bytes = crypto.randomBytes(16)',
  );

  final _secureRandom = Random.secure();

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('randomBytes requires 1 argument: number of bytes');
    }
    final count = rawLuaSlot(args[0]) as int;
    if (count <= 0 || count > 1024) {
      throw LuaError('Byte count must be between 1 and 1024');
    }
    final bytes = Uint8List(count);
    for (var i = 0; i < count; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return valueFromOptionalLuaSlot(interpreter, bytes);
  }
}

class _AesCbcFunction extends BuiltinFunction {
  final bool _encrypt;

  _AesCbcFunction(this._encrypt, super.interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Encrypts or decrypts data using AES-CBC.',
    params: [
      DocParam('mode', 'string', '"encrypt" or "decrypt".'),
      DocParam('key', 'string', 'The AES key (16, 24, or 32 bytes).'),
      DocParam('iv', 'string', 'The initialization vector (16 bytes).'),
      DocParam('data', 'string', 'The data to encrypt or decrypt.'),
    ],
    returns: 'The encrypted or decrypted string.',
    category: 'crypto',
    example: 'crypto.aesCbc("encrypt", key, iv, data)',
  );

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 3) {
      throw LuaError(
        'aesEncrypt/aesDecrypt requires 3 arguments: key, iv, and data',
      );
    }

    final key = _toBytes(args[0]);
    final iv = _toBytes(args[1]);
    final data = _toBytes(args[2]);

    if (key.length != 16 && key.length != 24 && key.length != 32) {
      throw LuaError('AES key must be 16, 24, or 32 bytes long');
    }

    if (iv.length != 16) {
      throw LuaError('AES IV must be 16 bytes long');
    }

    final cipher = pc.PaddedBlockCipher('AES/CBC/PKCS7');
    final params = pc.PaddedBlockCipherParameters(
      pc.ParametersWithIV(pc.KeyParameter(key), iv),
      null,
    );
    cipher.init(_encrypt, params);

    try {
      final result = cipher.process(data);
      return valueFromOptionalLuaSlot(interpreter, result);
    } catch (e) {
      throw LuaError('Failed to ${_encrypt ? 'encrypt' : 'decrypt'} data: $e');
    }
  }
}
