import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:convert/convert.dart' show hex;
import 'package:lualike/src/builtin_function.dart';

import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/value.dart';
import 'package:lualike/src/lua_string.dart';
import 'library.dart';

/// Crypto library implementation using the new Library system
class CryptoLibrary extends Library {
  @override
  String get name => "crypto";

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

Uint8List _toBytes(Value value) {
  final raw = value.raw;
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
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('hash function requires 1 argument');
    }
    final input = _toBytes(args[0] as Value);
    final digest = _hash.convert(input);
    return Value(digest.toString());
  }
}

class HmacFunction extends BuiltinFunction {
  HmacFunction(super.interpreter);
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 3) {
      throw LuaError(
        'hmac requires 3 arguments: digest name, key, and message',
      );
    }

    final digestName = (args[0] as Value).raw.toString();
    final key = _toBytes(args[1] as Value);
    final message = _toBytes(args[2] as Value);

    try {
      final hmac = pc.Mac('$digestName/HMAC');
      hmac.init(pc.KeyParameter(key));
      final result = hmac.process(message);
      return Value(hex.encode(result));
    } catch (e) {
      throw LuaError('Failed to compute HMAC: $e');
    }
  }
}

class RandomBytesFunction extends BuiltinFunction {
  RandomBytesFunction(super.interpreter);
  final _secureRandom = Random.secure();

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError('randomBytes requires 1 argument: number of bytes');
    }
    final count = (args[0] as Value).raw as int;
    if (count <= 0 || count > 1024) {
      throw LuaError('Byte count must be between 1 and 1024');
    }
    final bytes = Uint8List(count);
    for (var i = 0; i < count; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return Value(bytes);
  }
}

class _AesCbcFunction extends BuiltinFunction {
  final bool _encrypt;

  _AesCbcFunction(this._encrypt, super.interpreter);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 3) {
      throw LuaError(
        'aesEncrypt/aesDecrypt requires 3 arguments: key, iv, and data',
      );
    }

    final key = _toBytes(args[0] as Value);
    final iv = _toBytes(args[1] as Value);
    final data = _toBytes(args[2] as Value);

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
      return Value(result);
    } catch (e) {
      throw LuaError('Failed to ${_encrypt ? 'encrypt' : 'decrypt'} data: $e');
    }
  }
}
