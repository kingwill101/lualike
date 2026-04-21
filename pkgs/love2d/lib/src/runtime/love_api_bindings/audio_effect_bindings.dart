part of '../love_api_bindings.dart';

enum _LoveAudioSettingValueKind { number, boolean, waveform }

typedef _LoveAudioSettingSchema = Map<String, _LoveAudioSettingValueKind>;

const _loveAudioEffectBasicSchema = <String, _LoveAudioSettingValueKind>{
  'volume': _LoveAudioSettingValueKind.number,
};

const _loveAudioEffectSchemas = <String, _LoveAudioSettingSchema>{
  'reverb': <String, _LoveAudioSettingValueKind>{
    'gain': _LoveAudioSettingValueKind.number,
    'highgain': _LoveAudioSettingValueKind.number,
    'density': _LoveAudioSettingValueKind.number,
    'diffusion': _LoveAudioSettingValueKind.number,
    'decaytime': _LoveAudioSettingValueKind.number,
    'decayhighratio': _LoveAudioSettingValueKind.number,
    'earlygain': _LoveAudioSettingValueKind.number,
    'earlydelay': _LoveAudioSettingValueKind.number,
    'lategain': _LoveAudioSettingValueKind.number,
    'latedelay': _LoveAudioSettingValueKind.number,
    'roomrolloff': _LoveAudioSettingValueKind.number,
    'airabsorption': _LoveAudioSettingValueKind.number,
    'highlimit': _LoveAudioSettingValueKind.boolean,
  },
  'chorus': <String, _LoveAudioSettingValueKind>{
    'waveform': _LoveAudioSettingValueKind.waveform,
    'phase': _LoveAudioSettingValueKind.number,
    'rate': _LoveAudioSettingValueKind.number,
    'depth': _LoveAudioSettingValueKind.number,
    'feedback': _LoveAudioSettingValueKind.number,
    'delay': _LoveAudioSettingValueKind.number,
  },
  'distortion': <String, _LoveAudioSettingValueKind>{
    'gain': _LoveAudioSettingValueKind.number,
    'edge': _LoveAudioSettingValueKind.number,
    'lowcut': _LoveAudioSettingValueKind.number,
    'center': _LoveAudioSettingValueKind.number,
    'bandwidth': _LoveAudioSettingValueKind.number,
  },
  'echo': <String, _LoveAudioSettingValueKind>{
    'delay': _LoveAudioSettingValueKind.number,
    'tapdelay': _LoveAudioSettingValueKind.number,
    'damping': _LoveAudioSettingValueKind.number,
    'feedback': _LoveAudioSettingValueKind.number,
    'spread': _LoveAudioSettingValueKind.number,
  },
  'flanger': <String, _LoveAudioSettingValueKind>{
    'waveform': _LoveAudioSettingValueKind.waveform,
    'phase': _LoveAudioSettingValueKind.number,
    'rate': _LoveAudioSettingValueKind.number,
    'depth': _LoveAudioSettingValueKind.number,
    'feedback': _LoveAudioSettingValueKind.number,
    'delay': _LoveAudioSettingValueKind.number,
  },
  'ringmodulator': <String, _LoveAudioSettingValueKind>{
    'waveform': _LoveAudioSettingValueKind.waveform,
    'frequency': _LoveAudioSettingValueKind.number,
    'highcut': _LoveAudioSettingValueKind.number,
  },
  'compressor': <String, _LoveAudioSettingValueKind>{
    'enable': _LoveAudioSettingValueKind.boolean,
  },
  'equalizer': <String, _LoveAudioSettingValueKind>{
    'lowgain': _LoveAudioSettingValueKind.number,
    'lowcut': _LoveAudioSettingValueKind.number,
    'lowmidgain': _LoveAudioSettingValueKind.number,
    'lowmidfrequency': _LoveAudioSettingValueKind.number,
    'lowmidbandwidth': _LoveAudioSettingValueKind.number,
    'highmidgain': _LoveAudioSettingValueKind.number,
    'highmidfrequency': _LoveAudioSettingValueKind.number,
    'highmidbandwidth': _LoveAudioSettingValueKind.number,
    'highgain': _LoveAudioSettingValueKind.number,
    'highcut': _LoveAudioSettingValueKind.number,
  },
};

const _loveAudioFilterBasicSchema = <String, _LoveAudioSettingValueKind>{
  'volume': _LoveAudioSettingValueKind.number,
};

const _loveAudioFilterSchemas = <String, _LoveAudioSettingSchema>{
  'lowpass': <String, _LoveAudioSettingValueKind>{
    'highgain': _LoveAudioSettingValueKind.number,
  },
  'highpass': <String, _LoveAudioSettingValueKind>{
    'lowgain': _LoveAudioSettingValueKind.number,
  },
  'bandpass': <String, _LoveAudioSettingValueKind>{
    'lowgain': _LoveAudioSettingValueKind.number,
    'highgain': _LoveAudioSettingValueKind.number,
  },
};

const Set<String> _loveAudioEffectWaveforms = <String>{
  'sine',
  'triangle',
  'sawtooth',
  'square',
};

LoveApiImplementation _bindAudioGetEffect(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    const symbol = 'love.audio.getEffect';
    final name = _requireString(args, 0, symbol);
    final settings = runtime.audio.effects.getEffect(name);
    if (settings == null) {
      return null;
    }

    return _audioSettingsTable(settings, targetArg: _valueAt(args, 1));
  };
}

LoveApiImplementation _bindAudioSetEffect(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    const symbol = 'love.audio.setEffect';
    final name = _requireString(args, 0, symbol);
    final settingsArg = _valueAt(args, 1);
    final rawSettings = _rawValue(settingsArg);

    if (rawSettings == null) {
      return runtime.audio.effects.unsetEffect(name);
    }

    if (rawSettings is bool && !rawSettings) {
      return runtime.audio.effects.unsetEffect(name);
    }

    final settings = _readAudioEffectSettings(
      settingsArg,
      symbol: symbol,
      argumentIndex: 2,
    );
    return runtime.audio.effects.setEffect(name, settings);
  };
}

LoveApiImplementation _bindSourceGetEffect(LibraryRegistrationContext context) {
  return (args) {
    const symbol = 'Source:getEffect';
    final source = _requireAudioSource(args, 0, symbol);
    final name = _requireString(args, 1, symbol);
    if (!source.effectState.hasEffect(name)) {
      return false;
    }

    final filter = source.effectState.getEffectFilter(name);
    if (filter == null) {
      return true;
    }

    return Value.multi(<Object?>[
      true,
      _audioSettingsTable(filter, targetArg: _valueAt(args, 2)),
    ]);
  };
}

LoveApiImplementation _bindSourceGetFilter(LibraryRegistrationContext context) {
  return (args) {
    final source = _requireAudioSource(args, 0, 'Source:getFilter');
    final filter = source.effectState.filter;
    if (filter == null) {
      return null;
    }

    return _audioSettingsTable(filter, targetArg: _valueAt(args, 1));
  };
}

LoveApiImplementation _bindSourceSetEffect(LibraryRegistrationContext context) {
  return (args) {
    const symbol = 'Source:setEffect';
    final source = _requireAudioSource(args, 0, symbol);
    final name = _requireString(args, 1, symbol);
    final filterArg = _valueAt(args, 2);
    final rawFilter = _rawValue(filterArg);

    if (rawFilter == null) {
      return source.effectState.setEffect(name);
    }

    if (rawFilter is bool) {
      return rawFilter
          ? source.effectState.setEffect(name)
          : source.effectState.unsetEffect(name);
    }

    final filter = _readAudioFilterSettings(
      filterArg,
      symbol: symbol,
      argumentIndex: 3,
    );
    return source.effectState.setEffect(name, filter: filter);
  };
}

LoveApiImplementation _bindSourceSetFilter(LibraryRegistrationContext context) {
  return (args) {
    const symbol = 'Source:setFilter';
    final source = _requireAudioSource(args, 0, symbol);
    final settingsArg = _valueAt(args, 1);
    if (_rawValue(settingsArg) == null) {
      return source.effectState.setFilter();
    }

    final filter = _readAudioFilterSettings(
      settingsArg,
      symbol: symbol,
      argumentIndex: 2,
    );
    return source.effectState.setFilter(filter);
  };
}

Object _audioSettingsTable(Map<String, Object?> settings, {Object? targetArg}) {
  final target = _tableTargetIfPresent(targetArg);
  if (target != null) {
    for (final entry in settings.entries) {
      target.$2[entry.key] = entry.value;
    }
    return target.$1;
  }

  return ValueClass.table(<Object?, Object?>{
    for (final entry in settings.entries) entry.key: entry.value,
  });
}

Value _audioStringListTable(Iterable<String> values) {
  final list = values.toList(growable: false);
  return ValueClass.table(<Object?, Object?>{
    for (var index = 0; index < list.length; index++) index + 1: list[index],
  });
}

Map<String, Object?> _readAudioEffectSettings(
  Object? value, {
  required String symbol,
  required int argumentIndex,
}) {
  return _readAudioSettingsTable(
    value,
    symbol: symbol,
    argumentIndex: argumentIndex,
    typeLabel: 'Effect',
    missingTypeMessage: 'Effect type not specificed.',
    schemas: _loveAudioEffectSchemas,
    basicSchema: _loveAudioEffectBasicSchema,
  );
}

Map<String, Object?> _readAudioFilterSettings(
  Object? value, {
  required String symbol,
  required int argumentIndex,
}) {
  return _readAudioSettingsTable(
    value,
    symbol: symbol,
    argumentIndex: argumentIndex,
    typeLabel: 'Filter',
    missingTypeMessage: 'Filter type not specificed.',
    schemas: _loveAudioFilterSchemas,
    basicSchema: _loveAudioFilterBasicSchema,
  );
}

Map<String, Object?> _readAudioSettingsTable(
  Object? value, {
  required String symbol,
  required int argumentIndex,
  required String typeLabel,
  required String missingTypeMessage,
  required Map<String, _LoveAudioSettingSchema> schemas,
  required _LoveAudioSettingSchema basicSchema,
}) {
  final table = _tableIfPresent(value);
  if (table == null) {
    throw LuaError('$symbol expected a table at argument $argumentIndex');
  }

  final typeName = _tableString(table, 'type');
  if (typeName == null) {
    throw LuaError(missingTypeMessage);
  }

  final typeSchema = schemas[typeName];
  if (typeSchema == null) {
    throw LuaError(
      '$symbol invalid ${typeLabel.toLowerCase()} type "$typeName"',
    );
  }

  final normalized = <String, Object?>{'type': typeName};
  final combinedSchema = <String, _LoveAudioSettingValueKind>{
    ...basicSchema,
    ...typeSchema,
  };

  for (final entry in table.entries) {
    final key = _stringLike(entry.key);
    if (key == null) {
      throw LuaError('$symbol expected string keys in settings table');
    }
    if (key == 'type') {
      continue;
    }

    final expectedKind = combinedSchema[key];
    if (expectedKind == null) {
      throw LuaError("Invalid '$typeName' Effect parameter: $key");
    }

    final raw = _rawValue(entry.value);
    normalized[key] = _validateAudioSettingValue(
      raw,
      expectedKind,
      typeName: typeName,
      key: key,
    );
  }

  return normalized;
}

Object _validateAudioSettingValue(
  Object? raw,
  _LoveAudioSettingValueKind expectedKind, {
  required String typeName,
  required String key,
}) {
  return switch (expectedKind) {
    _LoveAudioSettingValueKind.number => switch (raw) {
      final num value => value.toDouble(),
      _ => throw LuaError(
        'Bad parameter type for $typeName $key: number expected, got ${_luaTypeName(raw)}',
      ),
    },
    _LoveAudioSettingValueKind.boolean => switch (raw) {
      final bool value => value,
      _ => throw LuaError(
        'Bad parameter type for $typeName $key: boolean expected, got ${_luaTypeName(raw)}',
      ),
    },
    _LoveAudioSettingValueKind.waveform => switch (_stringLike(raw)) {
      final String waveform when _loveAudioEffectWaveforms.contains(waveform) =>
        waveform,
      final String waveform => throw LuaError(
        'Invalid waveform type: $waveform',
      ),
      _ => throw LuaError(
        'Bad parameter type for $typeName $key: string expected, got ${_luaTypeName(raw)}',
      ),
    },
  };
}

String _luaTypeName(Object? value) {
  final raw = _rawValue(value);
  return switch (raw) {
    null => 'nil',
    bool _ => 'boolean',
    num _ => 'number',
    String _ || LuaString _ => 'string',
    Map<dynamic, dynamic> _ => 'table',
    BuiltinFunction _ || Function _ => 'function',
    _ => raw.runtimeType.toString(),
  };
}
