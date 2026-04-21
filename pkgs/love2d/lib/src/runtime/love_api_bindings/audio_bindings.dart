part of '../love_api_bindings.dart';

class _LoveAudioSourceInput {
  const _LoveAudioSourceInput({
    required this.source,
    required this.filename,
    required this.defaultSourceType,
    this.fixedSourceType,
    this.bytes,
    this.mimeType,
    this.durationSeconds = -1.0,
    this.durationSamples = -1,
    this.sampleRate = 0,
    this.bitDepth = 0,
    this.channelCount = 2,
  });

  final String source;
  final String? filename;
  final String defaultSourceType;
  final String? fixedSourceType;
  final Uint8List? bytes;
  final String? mimeType;
  final double durationSeconds;
  final int durationSamples;
  final int sampleRate;
  final int bitDepth;
  final int channelCount;
}

LoveApiImplementation _bindAudioGetActiveEffects(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) =>
      _audioStringListTable(runtime.audio.effects.activeEffectNames);
}

LoveApiImplementation _bindAudioGetActiveSourceCount(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.audio.activeSourceCount;
}

LoveApiImplementation _bindAudioGetDistanceModel(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.audio.distanceModel;
}

LoveApiImplementation _bindAudioGetDopplerScale(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.audio.dopplerScale;
}

LoveApiImplementation _bindAudioGetMaxSceneEffects(
  LibraryRegistrationContext context,
) {
  return (args) => loveAudioMaxSceneEffects;
}

LoveApiImplementation _bindAudioGetMaxSourceEffects(
  LibraryRegistrationContext context,
) {
  return (args) => loveAudioMaxSourceEffects;
}

LoveApiImplementation _bindAudioGetOrientation(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final forward = runtime.audio.orientationForward;
    final up = runtime.audio.orientationUp;
    return Value.multi(<Object?>[
      forward.x,
      forward.y,
      forward.z,
      up.x,
      up.y,
      up.z,
    ]);
  };
}

LoveApiImplementation _bindAudioGetPosition(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final position = runtime.audio.position;
    return Value.multi(<Object?>[position.x, position.y, position.z]);
  };
}

LoveApiImplementation _bindAudioGetRecordingDevices(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) =>
      Value(_recordingDeviceTable(context, runtime.audio.recordingDevices));
}

LoveApiImplementation _bindAudioGetVelocity(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final velocity = runtime.audio.velocity;
    return Value.multi(<Object?>[velocity.x, velocity.y, velocity.z]);
  };
}

LoveApiImplementation _bindAudioGetVolume(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.audio.volume;
}

LoveApiImplementation _bindAudioIsEffectsSupported(
  LibraryRegistrationContext context,
) {
  return (args) => true;
}

LoveApiImplementation _bindAudioNewSource(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) async {
    const symbol = 'love.audio.newSource';
    final sourceValue = _valueAt(args, 0);
    final input = await _requireAudioSourceInput(context, sourceValue, symbol);
    final requestedSourceType = args.length >= 2
        ? _requireAudioSourceType(args, 1, symbol)
        : input.defaultSourceType;
    if (requestedSourceType == 'queue' && input.fixedSourceType == null) {
      throw LuaError(
        'love.audio.newSource cannot create queueable sources. '
        'Use love.audio.newQueueableSource instead.',
      );
    }

    final sourceType = input.fixedSourceType ?? requestedSourceType;

    final audioSource = runtime.audio.newSource(
      sourceType: sourceType,
      source: input.source,
      filename: input.filename,
      backend: await runtime.host.createAudioSourceBackend(
        input.source,
        sourceType: sourceType,
        bytes: input.bytes,
        mimeType: input.mimeType,
      ),
      bytes: input.bytes,
      mimeType: input.mimeType,
      durationSeconds: input.durationSeconds,
      durationSamples: input.durationSamples,
      sampleRate: input.sampleRate,
      bitDepth: input.bitDepth,
      channelCount: input.channelCount,
    );
    return _wrapAudioSource(context, audioSource);
  };
}

LoveApiImplementation _bindAudioNewQueueableSource(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    const symbol = 'love.audio.newQueueableSource';
    final sampleRate = _requireRoundedInt(args, 0, symbol);
    final bitDepth = _requireRoundedInt(args, 1, symbol);
    final channels = _requireRoundedInt(args, 2, symbol);
    final bufferCount = args.length >= 4
        ? _requireRoundedInt(args, 3, symbol)
        : 0;

    _validateAudioQueueMetadata(
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      channels: channels,
    );

    final resolvedBufferCount = bufferCount < 1
        ? loveAudioDefaultQueueBufferCount
        : math.min(bufferCount, loveAudioMaxQueueBufferCount);

    final audioSource = runtime.audio.newSource(
      sourceType: 'queue',
      source: 'queue',
      filename: null,
      durationSeconds: 0.0,
      durationSamples: 0,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      channelCount: channels,
      queueBufferCount: resolvedBufferCount,
    );
    return _wrapAudioSource(context, audioSource);
  };
}

LoveApiImplementation _bindAudioPause(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) async {
    final sources = _audioSourceSequence(args, 'love.audio.pause');
    final paused = await runtime.audio.pause(sources.isEmpty ? null : sources);
    return args.isEmpty ? Value(_audioSourceTable(context, paused)) : null;
  };
}

LoveApiImplementation _bindAudioPlay(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) async {
    await runtime.audio.play(_audioSourceSequence(args, 'love.audio.play'));
    return true;
  };
}

LoveApiImplementation _bindAudioSetDistanceModel(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.audio.distanceModel = _requireAudioDistanceModel(
      args,
      0,
      'love.audio.setDistanceModel',
    );
    return null;
  };
}

LoveApiImplementation _bindAudioSetDopplerScale(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.audio.dopplerScale = _requireNumber(
      args,
      0,
      'love.audio.setDopplerScale',
    );
    return null;
  };
}

LoveApiImplementation _bindAudioSetMixWithSystem(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.audio.mixWithSystem = _requireBoolean(
      args,
      0,
      'love.audio.setMixWithSystem',
    );
    return null;
  };
}

LoveApiImplementation _bindAudioSetOrientation(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.audio.orientationForward = Vector3(
      _requireNumber(args, 0, 'love.audio.setOrientation'),
      _requireNumber(args, 1, 'love.audio.setOrientation'),
      _requireNumber(args, 2, 'love.audio.setOrientation'),
    );
    runtime.audio.orientationUp = Vector3(
      _requireNumber(args, 3, 'love.audio.setOrientation'),
      _requireNumber(args, 4, 'love.audio.setOrientation'),
      _requireNumber(args, 5, 'love.audio.setOrientation'),
    );
    return null;
  };
}

LoveApiImplementation _bindAudioSetPosition(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.audio.position = Vector3(
      _requireNumber(args, 0, 'love.audio.setPosition'),
      _requireNumber(args, 1, 'love.audio.setPosition'),
      args.length >= 3 ? _requireNumber(args, 2, 'love.audio.setPosition') : 0,
    );
    return null;
  };
}

LoveApiImplementation _bindAudioSetVelocity(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.audio.velocity = Vector3(
      _requireNumber(args, 0, 'love.audio.setVelocity'),
      _requireNumber(args, 1, 'love.audio.setVelocity'),
      args.length >= 3 ? _requireNumber(args, 2, 'love.audio.setVelocity') : 0,
    );
    return null;
  };
}

LoveApiImplementation _bindAudioSetVolume(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.audio.volume = _requireNumber(args, 0, 'love.audio.setVolume');
    return null;
  };
}

LoveApiImplementation _bindAudioStop(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) async {
    await runtime.audio.stop(
      args.isEmpty ? null : _audioSourceSequence(args, 'love.audio.stop'),
    );
    return null;
  };
}

String _requireAudioSourceType(List<Object?> args, int index, String symbol) {
  final value = _requireString(args, index, symbol);
  if (!loveAudioSourceTypes.contains(value)) {
    throw LuaError('$symbol invalid SourceType "$value"');
  }
  return value;
}

void _validateAudioQueueMetadata({
  required int sampleRate,
  required int bitDepth,
  required int channels,
}) {
  if (sampleRate <= 0) {
    throw LuaError('Invalid sample rate: $sampleRate');
  }
  if (bitDepth != 8 && bitDepth != 16) {
    throw LuaError('Invalid bit depth: $bitDepth');
  }
  if (channels < 1 || channels > 2) {
    throw LuaError('Invalid channel count: $channels');
  }
}

String _audioTimeUnitAt(List<Object?> args, int index, String symbol) {
  if (args.length <= index || _rawValue(_valueAt(args, index)) == null) {
    return 'seconds';
  }

  final value = _requireString(args, index, symbol);
  if (!loveAudioTimeUnits.contains(value)) {
    throw LuaError('$symbol invalid TimeUnit "$value"');
  }
  return value;
}

String _requireAudioDistanceModel(
  List<Object?> args,
  int index,
  String symbol,
) {
  final value = _requireString(args, index, symbol);
  if (!loveAudioDistanceModels.contains(value)) {
    throw LuaError('$symbol invalid DistanceModel "$value"');
  }
  return value;
}

LoveApiImplementation _bindSourcePlay(LibraryRegistrationContext context) {
  return (args) async {
    return await _requireAudioSource(args, 0, 'Source:play').play();
  };
}

LoveApiImplementation _bindSourceSetLooping(
  LibraryRegistrationContext context,
) {
  return (args) async {
    final source = _requireAudioSource(args, 0, 'Source:setLooping');
    final looping = _requireBoolean(args, 1, 'Source:setLooping');
    if (source.sourceType == 'queue' && looping) {
      throw LuaError('Queueable Sources can not be looped.');
    }
    await source.setLooping(looping);
    return null;
  };
}

LoveApiImplementation _bindSourceQueue(LibraryRegistrationContext context) {
  return (args) => _queueSourceInput(args, 'Source:queue');
}

Future<_LoveAudioSourceInput> _requireAudioSourceInput(
  LibraryRegistrationContext context,
  Object? sourceValue,
  String symbol,
) async {
  final soundData = _soundDataIfPresent(sourceValue);
  if (soundData != null) {
    return _LoveAudioSourceInput(
      source: 'sounddata.wav',
      filename: 'sounddata.wav',
      defaultSourceType: 'static',
      fixedSourceType: 'static',
      bytes: loveEncodeSoundDataAsWaveBytes(soundData),
      mimeType: 'audio/wav',
      durationSeconds: soundData.duration,
      durationSamples: soundData.sampleCount,
      sampleRate: soundData.sampleRate,
      bitDepth: soundData.bitDepth,
      channelCount: soundData.channels,
    );
  }

  final decoder = _decoderIfPresent(sourceValue);
  if (decoder != null) {
    final decoded = decoder.clone().decodeAllRemaining();
    return _LoveAudioSourceInput(
      source: 'decoder.wav',
      filename: 'decoder.wav',
      defaultSourceType: 'stream',
      bytes: loveEncodeSoundDataAsWaveBytes(decoded),
      mimeType: 'audio/wav',
      durationSeconds: decoded.duration,
      durationSamples: decoded.sampleCount,
      sampleRate: decoded.sampleRate,
      bitDepth: decoded.bitDepth,
      channelCount: decoded.channels,
    );
  }

  final fileData = await _requireResourceFileData(context, sourceValue, symbol);
  return _LoveAudioSourceInput(
    source: fileData.filename,
    filename: fileData.filename,
    defaultSourceType: 'stream',
    bytes: Uint8List.fromList(fileData.bytes),
    mimeType: loveAudioMimeTypeFromFilename(fileData.filename),
  );
}

List<LoveAudioSource> _audioSourceSequence(List<Object?> args, String symbol) {
  if (args.isEmpty) {
    return const <LoveAudioSource>[];
  }

  if (args.length == 1) {
    final source = _audioSourceIfPresent(args.first);
    if (source != null) {
      return <LoveAudioSource>[source];
    }
  }

  final table = args.length == 1 ? _tableIfPresent(args.first) : null;
  if (table != null) {
    final sources = <LoveAudioSource>[];
    for (var index = 1; ; index++) {
      final entry = _tableIndexedEntry(table, index);
      if (entry == null) {
        break;
      }
      final source = _audioSourceIfPresent(entry);
      if (source == null) {
        throw LuaError('$symbol expected Source values in table argument');
      }
      sources.add(source);
    }
    return sources;
  }

  return List<LoveAudioSource>.generate(
    args.length,
    (index) => _requireAudioSource(args, index, symbol),
    growable: false,
  );
}

LoveSoundData _queueSoundDataSlice(
  List<Object?> args,
  LoveSoundData soundData,
  String symbol,
) {
  var offset = 0;
  var length = soundData.bytes.length;
  if (args.length >= 4) {
    offset = _requireRoundedInt(args, 2, symbol);
    length = _requireRoundedInt(args, 3, symbol);
  } else if (args.length >= 3) {
    length = _requireRoundedInt(args, 2, symbol);
  }

  if (offset < 0 || length < 0 || length > soundData.bytes.length - offset) {
    throw LuaError('Data region out of bounds.');
  }
  if (length % soundData.frameByteSize != 0) {
    throw LuaError(
      'Data length must be a multiple of sample size (${soundData.frameByteSize} bytes).',
    );
  }

  final frameOffset = offset ~/ soundData.frameByteSize;
  final frameCount = length ~/ soundData.frameByteSize;
  return soundData.copyFrames(frameOffset, frameCount);
}

Object _queueSourceInput(List<Object?> args, String symbol) {
  final source = _requireAudioSource(args, 0, symbol);
  final soundData = _soundDataIfPresent(_valueAt(args, 1));
  if (soundData != null) {
    return _queueResolvedSoundData(
      source,
      _queueSoundDataSlice(args, soundData, symbol),
    );
  }

  final pointer = _dataPointerIfPresent(_valueAt(args, 1));
  if (pointer != null) {
    return _queueResolvedSoundData(
      source,
      _queueLightUserdata(args, pointer, symbol),
    );
  }

  throw LuaError('$symbol expected SoundData or lightuserdata at argument 2');
}

Object _queueResolvedSoundData(LoveAudioSource source, LoveSoundData queued) {
  try {
    return source.queueSoundData(queued);
  } on ArgumentError catch (error) {
    throw LuaError(error.message.toString());
  }
}

LoveSoundData _queueLightUserdata(
  List<Object?> args,
  LoveDataPointer pointer,
  String symbol,
) {
  final offset = _requireRoundedInt(args, 2, symbol);
  final length = _requireRoundedInt(args, 3, symbol);
  final sampleRate = _requireRoundedInt(args, 4, symbol);
  final bitDepth = _requireRoundedInt(args, 5, symbol);
  final channels = _requireRoundedInt(args, 6, symbol);

  final bytes = pointer.bytes;
  if (offset < 0 ||
      length < 0 ||
      offset > bytes.length ||
      length > bytes.length - offset) {
    throw LuaError('Data region out of bounds.');
  }

  try {
    return LoveSoundData.fromPcmBytes(
      bytes: bytes.sublist(offset, offset + length),
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      channels: channels,
    );
  } on ArgumentError catch (error) {
    throw LuaError(error.message.toString());
  }
}
