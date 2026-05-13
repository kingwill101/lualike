part of '../love_api_bindings.dart';

const String _loveDecoderReleasedWrapperKey = '__love2d_decoder_released__';

/// Returns the Lua wrapper table for a `Decoder`, including released wrappers.
Map<dynamic, dynamic>? _decoderWrapperTableIfPresent(Object? value) {
  final table = _tableIdentityIfPresent(value);
  if (table == null) {
    return null;
  }

  final decoder = table[_loveDecoderObjectKey];
  if (decoder is LoveSoundDecoder ||
      table[_loveDecoderReleasedWrapperKey] == true) {
    return table;
  }

  return null;
}

/// Returns whether [value] is a released `Decoder` wrapper.
bool _decoderWrapperReleased(Object? value) {
  final table = _decoderWrapperTableIfPresent(value);
  return table?[_loveDecoderReleasedWrapperKey] == true;
}

/// Returns wrapped [LoveSoundData] when [value] is a SoundData table.
LoveSoundData? _soundDataIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final data = table[_loveSoundDataObjectKey];
  return data is LoveSoundData ? data : null;
}

/// Returns wrapped [LoveSoundDecoder] when [value] is a Decoder table.
LoveSoundDecoder? _decoderIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final decoder = table[_loveDecoderObjectKey];
  return decoder is LoveSoundDecoder ? decoder : null;
}

/// Returns a required `SoundData` receiver.
LoveSoundData _requireSoundData(List<Object?> args, int index, String symbol) {
  final value = _valueAt(args, index);
  final data = _soundDataIfPresent(value);
  if (data != null) {
    if (_loveDataReleased[data] == true) {
      _throwReleasedObjectError();
    }
    return data;
  }

  _throwLuaStyleTypeError(
    symbol: symbol,
    index: index,
    expected: 'SoundData',
    actual: value,
  );
}

/// Returns a required `Decoder` receiver.
LoveSoundDecoder _requireDecoder(List<Object?> args, int index, String symbol) {
  final value = _valueAt(args, index);
  if (_decoderWrapperReleased(value)) {
    _throwReleasedObjectError();
  }

  final decoder = _decoderIfPresent(value);
  if (decoder != null) {
    return decoder;
  }

  _throwLuaStyleTypeError(
    symbol: symbol,
    index: index,
    expected: 'Decoder',
    actual: value,
  );
}

/// Wraps [data] as a Lua-facing `SoundData` object table.
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

/// Wraps [decoder] as a Lua-facing `Decoder` object table.
Value _wrapDecoder(
  LibraryRegistrationContext context,
  LoveSoundDecoder decoder,
) {
  final cached = _loveDecoderWrapperCache[decoder];
  if (cached != null && _decoderIfPresent(cached) != null) {
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
        final receiver = _valueAt(args, 0);
        final table = _decoderWrapperTableIfPresent(receiver);
        if (table == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:release',
            index: 0,
            expected: 'Decoder',
            actual: receiver,
          );
        }

        final decoder = table[_loveDecoderObjectKey];
        if (decoder is! LoveSoundDecoder) {
          return false;
        }
        if (_loveDecoderReleased[decoder] == true) {
          return false;
        }

        _loveDecoderReleased[decoder] = true;
        table[_loveDecoderReleasedWrapperKey] = true;
        table[_loveDecoderObjectKey] = null;
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
    'type': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_decoderWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:type',
            index: 0,
            expected: 'Decoder',
            actual: receiver,
          );
        }
        return 'Decoder';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_decoderWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:typeOf',
            index: 0,
            expected: 'Decoder',
            actual: receiver,
          );
        }
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });
  _loveDecoderWrapperCache[decoder] = table;
  return table;
}

/// Converts a Lua sample index argument to the integer form used internally.
int _soundSampleIndex(List<Object?> args, int index, String symbol) {
  return _requireNumber(args, index, symbol).floor();
}

/// Rewraps sound-domain [ArgumentError] failures as [LuaError].
T _soundGuard<T>(T Function() callback) {
  try {
    return callback();
  } on ArgumentError catch (error) {
    throw LuaError(error.message);
  }
}
