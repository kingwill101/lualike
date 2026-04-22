part of '../love_api_bindings.dart';

LoveFilesystemFile? _soundFilesystemFileIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final file = table[_loveFilesystemFileObjectKeyCompat];
  return file is LoveFilesystemFile ? file : null;
}

Future<LoveFilesystemFileData> _requireSoundFileData(
  LibraryRegistrationContext context,
  Object? source,
  String functionName,
) async {
  final compat = _filesystemFileDataCompatIfPresent(source);
  if (compat != null) {
    return compat;
  }

  final filename = _stringLike(source);
  if (filename != null) {
    final mounted = await _readMountedResourceFileData(
      context,
      filename,
      symbol: 'love.sound.$functionName',
    );
    if (mounted != null) {
      return mounted;
    }

    throw _missingResourceFileError(filename);
  }

  if (_soundFilesystemFileIfPresent(source) != null) {
    final coerced = await _coerceResourceFileDataViaFilesystem(
      context,
      source,
      'love.sound.$functionName',
    );
    if (coerced != null) {
      return coerced;
    }
  }

  throw LuaError(
    "bad argument #1 to '$functionName' "
    '(filename, File, or FileData expected)',
  );
}

/// Binds `love.sound.newDecoder`.
///
/// LOVE accepts any resource-backed audio input here and turns it into a
/// streaming decoder with an optional buffer size override.
LoveApiImplementation _bindSoundNewDecoder(LibraryRegistrationContext context) {
  return (args) async {
    const symbol = 'love.sound.newDecoder';
    final fileData = await _requireSoundFileData(
      context,
      _valueAt(args, 0),
      'newDecoder',
    );
    final bufferSize = args.length >= 2
        ? _requireLuaStyleRoundedInt(args, 1, symbol)
        : loveSoundDefaultBufferSize;

    try {
      return _wrapDecoder(
        context,
        loveNewSoundDecoderFromBytes(
          fileData.bytes,
          source: fileData.filename,
          bufferSize: bufferSize,
        ),
      );
    } on UnsupportedError catch (error) {
      final message = error.message ?? error.toString();
      throw LuaError(message);
    } on ArgumentError catch (error) {
      final message = error.message;
      throw LuaError(
        message is String && message.isNotEmpty
            ? message
            : '$symbol failed to decode audio data.',
      );
    }
  };
}

/// Binds `love.sound.newSoundData`.
///
/// LOVE overloads this call to create silent sound data from numeric
/// parameters, decode all remaining samples from a `Decoder`, or decode a file
/// directly from bytes.
LoveApiImplementation _bindSoundNewSoundData(
  LibraryRegistrationContext context,
) {
  return (args) async {
    const symbol = 'love.sound.newSoundData';
    final first = _valueAt(args, 0);
    final rawFirst = _rawValue(first);
    if (rawFirst is num) {
      final samples = rawFirst.round();
      final sampleRate = args.length >= 2
          ? _requireLuaStyleRoundedInt(args, 1, symbol)
          : loveSoundDefaultSampleRate;
      final bitDepth = args.length >= 3
          ? _requireLuaStyleRoundedInt(args, 2, symbol)
          : loveSoundDefaultBitDepth;
      final channels = args.length >= 4
          ? _requireLuaStyleRoundedInt(args, 3, symbol)
          : loveSoundDefaultChannels;

      try {
        return _wrapSoundData(
          context,
          LoveSoundData.silence(
            samples: samples,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            channels: channels,
          ),
        );
      } on ArgumentError catch (error) {
        final message = error.message;
        throw LuaError(
          message is String && message.isNotEmpty
              ? message
              : '$symbol failed to construct SoundData.',
        );
      }
    }

    final decoder = _decoderIfPresent(first);
    if (decoder != null) {
      return _wrapSoundData(context, decoder.decodeAllRemaining());
    }

    final fileData = await _requireSoundFileData(
      context,
      first,
      'newSoundData',
    );
    try {
      return _wrapSoundData(
        context,
        loveDecodeSoundFile(bytes: fileData.bytes, source: fileData.filename),
      );
    } on UnsupportedError catch (error) {
      final message = error.message ?? error.toString();
      throw LuaError(message);
    } on ArgumentError catch (error) {
      final message = error.message;
      throw LuaError(
        message is String && message.isNotEmpty
            ? message
            : '$symbol failed to decode audio data.',
      );
    }
  };
}
