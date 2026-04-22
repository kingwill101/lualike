part of '../love_api_bindings.dart';

LoveAudioSource? _audioSourceIfPresent(Object? value) {
  final raw = _rawValue(value);
  final table = switch (raw) {
    final Map<dynamic, dynamic> map => map,
    _ => null,
  };

  if (table == null) {
    return null;
  }

  final source = table[_loveAudioSourceObjectKey];
  return source is LoveAudioSource ? source : null;
}

LoveAudioSource _requireAudioSource(
  List<Object?> args,
  int index,
  String symbol,
) {
  final source = _audioSourceIfPresent(_valueAt(args, index));
  if (source != null) {
    return source;
  }

  throw LuaError('$symbol expected a Source at argument ${index + 1}');
}

Map<Object?, Object?> _audioSourceTable(
  LibraryRegistrationContext context,
  Iterable<LoveAudioSource> sources,
) {
  final table = <Object?, Object?>{};
  var index = 1;
  for (final source in sources) {
    table[index++] = _wrapAudioSource(context, source);
  }
  return table;
}

Value _wrapAudioSource(
  LibraryRegistrationContext context,
  LoveAudioSource source,
) {
  final cached = _loveAudioSourceWrapperCache[source];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  const hierarchy = <String>{'Source', 'Object'};
  final table = ValueClass.table(<Object?, Object?>{
    _loveAudioSourceObjectKey: source,
    'clone': Value(
      builder.create((args) {
        final clone = _requireAudioSource(args, 0, 'Source:clone').clone();
        return _wrapAudioSource(context, clone);
      }),
      functionName: 'clone',
    ),
    'getActiveEffects': Value(
      builder.create((args) {
        final source = _requireAudioSource(args, 0, 'Source:getActiveEffects');
        return _audioStringListTable(source.effectState.activeEffectNames);
      }),
      functionName: 'getActiveEffects',
    ),
    'getAirAbsorption': Value(
      builder.create(
        (args) => _requireAudioSource(
          args,
          0,
          'Source:getAirAbsorption',
        ).airAbsorption,
      ),
      functionName: 'getAirAbsorption',
    ),
    'getAttenuationDistances': Value(
      builder.create((args) {
        final source = _requireAudioSource(
          args,
          0,
          'Source:getAttenuationDistances',
        );
        return Value.multi(<Object?>[
          source.referenceDistance,
          source.maxDistance,
        ]);
      }),
      functionName: 'getAttenuationDistances',
    ),
    'getChannelCount': Value(
      builder.create(
        (args) =>
            _requireAudioSource(args, 0, 'Source:getChannelCount').channelCount,
      ),
      functionName: 'getChannelCount',
    ),
    'getChannels': Value(
      builder.create(
        (args) =>
            _requireAudioSource(args, 0, 'Source:getChannels').channelCount,
      ),
      functionName: 'getChannels',
    ),
    'getCone': Value(
      builder.create((args) {
        final source = _requireAudioSource(args, 0, 'Source:getCone');
        return Value.multi(<Object?>[
          source.coneInnerAngle,
          source.coneOuterAngle,
          source.coneOuterVolume,
          source.coneOuterHighGain,
        ]);
      }),
      functionName: 'getCone',
    ),
    'getDirection': Value(
      builder.create((args) {
        final direction = _requireAudioSource(
          args,
          0,
          'Source:getDirection',
        ).direction;
        return Value.multi(<Object?>[direction.x, direction.y, direction.z]);
      }),
      functionName: 'getDirection',
    ),
    'getDuration': Value(
      builder.create((args) {
        final source = _requireAudioSource(args, 0, 'Source:getDuration');
        return source.getDuration(
          _audioTimeUnitAt(args, 1, 'Source:getDuration'),
        );
      }),
      functionName: 'getDuration',
    ),
    'getEffect': Value(
      builder.create(_bindSourceGetEffect(context)),
      functionName: 'getEffect',
    ),
    'getFilter': Value(
      builder.create(_bindSourceGetFilter(context)),
      functionName: 'getFilter',
    ),
    'getFreeBufferCount': Value(
      builder.create(
        (args) => _requireAudioSource(
          args,
          0,
          'Source:getFreeBufferCount',
        ).freeBufferCount,
      ),
      functionName: 'getFreeBufferCount',
    ),
    'getPitch': Value(
      builder.create(
        (args) => _requireAudioSource(args, 0, 'Source:getPitch').pitch,
      ),
      functionName: 'getPitch',
    ),
    'getPosition': Value(
      builder.create((args) {
        final position = _requireAudioSource(
          args,
          0,
          'Source:getPosition',
        ).position;
        return Value.multi(<Object?>[position.x, position.y, position.z]);
      }),
      functionName: 'getPosition',
    ),
    'getRolloff': Value(
      builder.create(
        (args) => _requireAudioSource(args, 0, 'Source:getRolloff').rolloff,
      ),
      functionName: 'getRolloff',
    ),
    'getType': Value(
      builder.create(
        (args) => _requireAudioSource(args, 0, 'Source:getType').sourceType,
      ),
      functionName: 'getType',
    ),
    'getVelocity': Value(
      builder.create((args) {
        final velocity = _requireAudioSource(
          args,
          0,
          'Source:getVelocity',
        ).velocity;
        return Value.multi(<Object?>[velocity.x, velocity.y, velocity.z]);
      }),
      functionName: 'getVelocity',
    ),
    'getVolume': Value(
      builder.create(
        (args) => _requireAudioSource(args, 0, 'Source:getVolume').volume,
      ),
      functionName: 'getVolume',
    ),
    'getVolumeLimits': Value(
      builder.create((args) {
        final source = _requireAudioSource(args, 0, 'Source:getVolumeLimits');
        return Value.multi(<Object?>[source.minVolume, source.maxVolume]);
      }),
      functionName: 'getVolumeLimits',
    ),
    'isLooping': Value(
      builder.create(
        (args) => _requireAudioSource(args, 0, 'Source:isLooping').looping,
      ),
      functionName: 'isLooping',
    ),
    'isPlaying': Value(
      builder.create(
        (args) => _requireAudioSource(args, 0, 'Source:isPlaying').playing,
      ),
      functionName: 'isPlaying',
    ),
    'isRelative': Value(
      builder.create(
        (args) => _requireAudioSource(args, 0, 'Source:isRelative').relative,
      ),
      functionName: 'isRelative',
    ),
    'pause': Value(
      builder.create((args) async {
        await _requireAudioSource(args, 0, 'Source:pause').pause();
        return null;
      }),
      functionName: 'pause',
    ),
    'play': Value(
      builder.create((args) async {
        return await _requireAudioSource(args, 0, 'Source:play').play();
      }),
      functionName: 'play',
    ),
    'queue': Value(
      builder.create((args) => _queueSourceInput(args, 'Source:queue')),
      functionName: 'queue',
    ),
    'seek': Value(
      builder.create((args) {
        final source = _requireAudioSource(args, 0, 'Source:seek');
        final offset = _requireNumber(args, 1, 'Source:seek');
        if (offset < 0.0) {
          throw LuaError("can't seek to a negative position");
        }
        source.seek(offset, unit: _audioTimeUnitAt(args, 2, 'Source:seek'));
        return null;
      }),
      functionName: 'seek',
    ),
    'setAirAbsorption': Value(
      builder.create((args) {
        final amount = _requireNumber(args, 1, 'Source:setAirAbsorption');
        if (amount < 0.0) {
          throw LuaError(
            'Invalid air absorption factor: $amount. Must be > 0.',
          );
        }
        _requireAudioSource(args, 0, 'Source:setAirAbsorption').airAbsorption =
            amount;
        return null;
      }),
      functionName: 'setAirAbsorption',
    ),
    'setAttenuationDistances': Value(
      builder.create((args) {
        final reference = _requireNumber(
          args,
          1,
          'Source:setAttenuationDistances',
        );
        final maximum = _requireNumber(
          args,
          2,
          'Source:setAttenuationDistances',
        );
        if (reference < 0.0 || maximum < 0.0) {
          throw LuaError(
            'Invalid distances: $reference, $maximum. Must be > 0',
          );
        }
        final source = _requireAudioSource(
          args,
          0,
          'Source:setAttenuationDistances',
        );
        source.referenceDistance = reference;
        source.maxDistance = maximum;
        return null;
      }),
      functionName: 'setAttenuationDistances',
    ),
    'setCone': Value(
      builder.create((args) {
        final source = _requireAudioSource(args, 0, 'Source:setCone');
        source.coneInnerAngle = _requireNumber(args, 1, 'Source:setCone');
        source.coneOuterAngle = _requireNumber(args, 2, 'Source:setCone');
        source.coneOuterVolume = args.length >= 4
            ? _requireNumber(args, 3, 'Source:setCone')
            : 0.0;
        source.coneOuterHighGain = args.length >= 5
            ? _requireNumber(args, 4, 'Source:setCone')
            : 1.0;
        return null;
      }),
      functionName: 'setCone',
    ),
    'setDirection': Value(
      builder.create((args) {
        _requireAudioSource(args, 0, 'Source:setDirection').direction = Vector3(
          _requireNumber(args, 1, 'Source:setDirection'),
          _requireNumber(args, 2, 'Source:setDirection'),
          args.length >= 4
              ? _requireNumber(args, 3, 'Source:setDirection')
              : 0.0,
        );
        return null;
      }),
      functionName: 'setDirection',
    ),
    'setEffect': Value(
      builder.create(_bindSourceSetEffect(context)),
      functionName: 'setEffect',
    ),
    'setFilter': Value(
      builder.create(_bindSourceSetFilter(context)),
      functionName: 'setFilter',
    ),
    'setLooping': Value(
      builder.create((args) async {
        final source = _requireAudioSource(args, 0, 'Source:setLooping');
        final looping = _requireBoolean(args, 1, 'Source:setLooping');
        if (source.sourceType == 'queue' && looping) {
          throw LuaError('Queueable Sources can not be looped.');
        }
        await source.setLooping(looping);
        return null;
      }),
      functionName: 'setLooping',
    ),
    'setPitch': Value(
      builder.create((args) {
        _requireAudioSource(args, 0, 'Source:setPitch').pitch = _requireNumber(
          args,
          1,
          'Source:setPitch',
        );
        return null;
      }),
      functionName: 'setPitch',
    ),
    'setPosition': Value(
      builder.create((args) {
        _requireAudioSource(args, 0, 'Source:setPosition').position = Vector3(
          _requireNumber(args, 1, 'Source:setPosition'),
          _requireNumber(args, 2, 'Source:setPosition'),
          args.length >= 4
              ? _requireNumber(args, 3, 'Source:setPosition')
              : 0.0,
        );
        return null;
      }),
      functionName: 'setPosition',
    ),
    'setRelative': Value(
      builder.create((args) {
        _requireAudioSource(args, 0, 'Source:setRelative').relative =
            _requireBoolean(args, 1, 'Source:setRelative');
        return null;
      }),
      functionName: 'setRelative',
    ),
    'setRolloff': Value(
      builder.create((args) {
        final rolloff = _requireNumber(args, 1, 'Source:setRolloff');
        if (rolloff < 0.0) {
          throw LuaError('Invalid rolloff: $rolloff. Must be > 0.');
        }
        _requireAudioSource(args, 0, 'Source:setRolloff').rolloff = rolloff;
        return null;
      }),
      functionName: 'setRolloff',
    ),
    'setVelocity': Value(
      builder.create((args) {
        _requireAudioSource(args, 0, 'Source:setVelocity').velocity = Vector3(
          _requireNumber(args, 1, 'Source:setVelocity'),
          _requireNumber(args, 2, 'Source:setVelocity'),
          args.length >= 4
              ? _requireNumber(args, 3, 'Source:setVelocity')
              : 0.0,
        );
        return null;
      }),
      functionName: 'setVelocity',
    ),
    'setVolume': Value(
      builder.create((args) {
        _requireAudioSource(args, 0, 'Source:setVolume').volume =
            _requireNumber(args, 1, 'Source:setVolume');
        return null;
      }),
      functionName: 'setVolume',
    ),
    'setVolumeLimits': Value(
      builder.create((args) {
        final minimum = _requireNumber(args, 1, 'Source:setVolumeLimits');
        final maximum = _requireNumber(args, 2, 'Source:setVolumeLimits');
        if (minimum < 0.0 || minimum > 1.0 || maximum < 0.0 || maximum > 1.0) {
          throw LuaError(
            'Invalid volume limits: [$minimum:$maximum]. Must be in [0:1]',
          );
        }
        final source = _requireAudioSource(args, 0, 'Source:setVolumeLimits');
        source.minVolume = minimum;
        source.maxVolume = maximum;
        return null;
      }),
      functionName: 'setVolumeLimits',
    ),
    'stop': Value(
      builder.create((args) async {
        await _requireAudioSource(args, 0, 'Source:stop').stop();
        return null;
      }),
      functionName: 'stop',
    ),
    'tell': Value(
      builder.create((args) {
        final source = _requireAudioSource(args, 0, 'Source:tell');
        return source.tell(_audioTimeUnitAt(args, 1, 'Source:tell'));
      }),
      functionName: 'tell',
    ),
    'type': Value(builder.create((args) => 'Source'), functionName: 'type'),
    'typeOf': Value(
      builder.create((args) {
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });
  _loveAudioSourceWrapperCache[source] = table;
  return table;
}
