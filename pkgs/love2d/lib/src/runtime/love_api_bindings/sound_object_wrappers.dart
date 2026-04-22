part of '../love_api_bindings.dart';

LoveSoundData? _soundDataIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final data = table[_loveSoundDataObjectKey];
  return data is LoveSoundData ? data : null;
}

LoveSoundDecoder? _decoderIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final decoder = table[_loveDecoderObjectKey];
  return decoder is LoveSoundDecoder ? decoder : null;
}

LoveSoundData _requireSoundData(List<Object?> args, int index, String symbol) {
  final data = _soundDataIfPresent(_valueAt(args, index));
  if (data != null) {
    return data;
  }

  throw LuaError('$symbol expected a SoundData at argument ${index + 1}');
}

LoveSoundDecoder _requireDecoder(List<Object?> args, int index, String symbol) {
  final decoder = _decoderIfPresent(_valueAt(args, index));
  if (decoder != null) {
    return decoder;
  }

  throw LuaError('$symbol expected a Decoder at argument ${index + 1}');
}

Value _wrapSoundData(LibraryRegistrationContext context, LoveSoundData data) {
  final cached = _loveSoundDataWrapperCache[data];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = _wrapLoveDataObject(
    context,
    rawObject: data,
    objectKey: _loveSoundDataObjectKey,
    typeName: 'SoundData',
    hierarchy: const <String>{'SoundData', 'Data', 'Object'},
    clone: (args) => _wrapSoundData(
      context,
      _requireSoundData(args, 0, 'Data:clone').clone(),
    ),
    extraEntries: <Object?, Object?>{
      'getBitDepth': Value(
        builder.create(
          (args) =>
              _requireSoundData(args, 0, 'SoundData:getBitDepth').bitDepth,
        ),
        functionName: 'getBitDepth',
      ),
      'getChannelCount': Value(
        builder.create(
          (args) =>
              _requireSoundData(args, 0, 'SoundData:getChannelCount').channels,
        ),
        functionName: 'getChannelCount',
      ),
      'getChannels': Value(
        builder.create(
          (args) =>
              _requireSoundData(args, 0, 'SoundData:getChannels').channels,
        ),
        functionName: 'getChannels',
      ),
      'getDuration': Value(
        builder.create(
          (args) =>
              _requireSoundData(args, 0, 'SoundData:getDuration').duration,
        ),
        functionName: 'getDuration',
      ),
      'getSample': Value(
        builder.create((args) {
          final soundData = _requireSoundData(args, 0, 'SoundData:getSample');
          final index = _soundSampleIndex(args, 1, 'SoundData:getSample');
          if (args.length >= 3 && _valueAt(args, 2) != null) {
            return _soundGuard(
              () => soundData.getSample(
                index,
                channel: _requireRoundedInt(args, 2, 'SoundData:getSample'),
              ),
            );
          }

          return _soundGuard(() => soundData.getSample(index));
        }),
        functionName: 'getSample',
      ),
      'getSampleCount': Value(
        builder.create(
          (args) => _requireSoundData(
            args,
            0,
            'SoundData:getSampleCount',
          ).sampleCount,
        ),
        functionName: 'getSampleCount',
      ),
      'getSampleRate': Value(
        builder.create(
          (args) =>
              _requireSoundData(args, 0, 'SoundData:getSampleRate').sampleRate,
        ),
        functionName: 'getSampleRate',
      ),
      'setSample': Value(
        builder.create((args) {
          final soundData = _requireSoundData(args, 0, 'SoundData:setSample');
          final index = _soundSampleIndex(args, 1, 'SoundData:setSample');
          if (args.length >= 4 && _valueAt(args, 3) != null) {
            _soundGuard(
              () => soundData.setSample(
                index,
                _requireNumber(args, 3, 'SoundData:setSample'),
                channel: _requireRoundedInt(args, 2, 'SoundData:setSample'),
              ),
            );
            return null;
          }

          _soundGuard(
            () => soundData.setSample(
              index,
              _requireNumber(args, 2, 'SoundData:setSample'),
            ),
          );
          return null;
        }),
        functionName: 'setSample',
      ),
    },
  );
  _loveSoundDataWrapperCache[data] = table;
  return table;
}

Value _wrapDecoder(
  LibraryRegistrationContext context,
  LoveSoundDecoder decoder,
) {
  final cached = _loveDecoderWrapperCache[decoder];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  const hierarchy = <String>{'Decoder', 'Object'};
  final table = ValueClass.table(<Object?, Object?>{
    _loveDecoderObjectKey: decoder,
    'clone': Value(
      builder.create(
        (args) => _wrapDecoder(
          context,
          _requireDecoder(args, 0, 'Decoder:clone').clone(),
        ),
      ),
      functionName: 'clone',
    ),
    'decode': Value(
      builder.create((args) {
        final decoder = _requireDecoder(args, 0, 'Decoder:decode');
        final chunk = decoder.decode();
        if (chunk == null) {
          return null;
        }
        return _wrapSoundData(context, chunk);
      }),
      functionName: 'decode',
    ),
    'getBitDepth': Value(
      builder.create(
        (args) => _requireDecoder(args, 0, 'Decoder:getBitDepth').bitDepth,
      ),
      functionName: 'getBitDepth',
    ),
    'getChannelCount': Value(
      builder.create(
        (args) => _requireDecoder(args, 0, 'Decoder:getChannelCount').channels,
      ),
      functionName: 'getChannelCount',
    ),
    'getChannels': Value(
      builder.create(
        (args) => _requireDecoder(args, 0, 'Decoder:getChannels').channels,
      ),
      functionName: 'getChannels',
    ),
    'getDuration': Value(
      builder.create(
        (args) => _requireDecoder(args, 0, 'Decoder:getDuration').duration,
      ),
      functionName: 'getDuration',
    ),
    'getSampleRate': Value(
      builder.create(
        (args) => _requireDecoder(args, 0, 'Decoder:getSampleRate').sampleRate,
      ),
      functionName: 'getSampleRate',
    ),
    'release': Value(
      builder.create((args) {
        final decoder = _requireDecoder(args, 0, 'Object:release');
        if (_loveDecoderReleased[decoder] == true) {
          return false;
        }

        _loveDecoderReleased[decoder] = true;
        return true;
      }),
      functionName: 'release',
    ),
    'seek': Value(
      builder.create((args) {
        final decoder = _requireDecoder(args, 0, 'Decoder:seek');
        final offset = _requireNumber(args, 1, 'Decoder:seek');
        if (offset < 0) {
          throw LuaError('Decoder:seek can\'t seek to a negative position');
        }
        if (offset == 0) {
          decoder.rewind();
        } else {
          decoder.seek(offset);
        }
        return null;
      }),
      functionName: 'seek',
    ),
    'type': Value(builder.create((args) => 'Decoder'), functionName: 'type'),
    'typeOf': Value(
      builder.create((args) {
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });
  _loveDecoderWrapperCache[decoder] = table;
  return table;
}

int _soundSampleIndex(List<Object?> args, int index, String symbol) {
  return _requireNumber(args, index, symbol).floor();
}

T _soundGuard<T>(T Function() callback) {
  try {
    return callback();
  } on ArgumentError catch (error) {
    throw LuaError(error.message);
  }
}
