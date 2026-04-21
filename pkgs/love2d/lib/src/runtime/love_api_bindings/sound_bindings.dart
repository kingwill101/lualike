part of '../love_api_bindings.dart';

LoveApiImplementation _bindSoundNewDecoder(LibraryRegistrationContext context) {
  return (args) async {
    const symbol = 'love.sound.newDecoder';
    if (args.isEmpty) {
      throw LuaError('$symbol expects at least 1 argument');
    }

    final fileData = await _requireResourceFileData(
      context,
      _valueAt(args, 0),
      symbol,
    );
    final bufferSize = args.length >= 2
        ? _requireRoundedInt(args, 1, symbol)
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
      if (message.startsWith('Extension ')) {
        throw LuaError('$symbol $message');
      }
      throw LuaError(
        '$symbol failed to decode "${fileData.filename}": $message',
      );
    } on ArgumentError catch (error) {
      throw LuaError(
        '$symbol failed to decode "${fileData.filename}": ${error.message}',
      );
    }
  };
}

LoveApiImplementation _bindSoundNewSoundData(
  LibraryRegistrationContext context,
) {
  return (args) async {
    const symbol = 'love.sound.newSoundData';
    if (args.isEmpty) {
      throw LuaError('$symbol expects at least 1 argument');
    }

    final first = _valueAt(args, 0);
    final rawFirst = _rawValue(first);
    if (rawFirst is num) {
      final samples = rawFirst.round();
      final sampleRate = args.length >= 2
          ? _requireRoundedInt(args, 1, symbol)
          : loveSoundDefaultSampleRate;
      final bitDepth = args.length >= 3
          ? _requireRoundedInt(args, 2, symbol)
          : loveSoundDefaultBitDepth;
      final channels = args.length >= 4
          ? _requireRoundedInt(args, 3, symbol)
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
        throw LuaError('$symbol ${error.message}');
      }
    }

    final decoder = _decoderIfPresent(first);
    if (decoder != null) {
      return _wrapSoundData(context, decoder.decodeAllRemaining());
    }

    final fileData = await _requireResourceFileData(context, first, symbol);
    try {
      return _wrapSoundData(
        context,
        loveDecodeSoundFile(bytes: fileData.bytes, source: fileData.filename),
      );
    } on UnsupportedError catch (error) {
      final message = error.message ?? error.toString();
      if (message.startsWith('Extension ')) {
        throw LuaError('$symbol $message');
      }
      throw LuaError(
        '$symbol failed to decode "${fileData.filename}": $message',
      );
    } on ArgumentError catch (error) {
      throw LuaError(
        '$symbol failed to decode "${fileData.filename}": ${error.message}',
      );
    }
  };
}
