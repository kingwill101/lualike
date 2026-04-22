part of '../love_api_bindings.dart';

/// Normalized metadata for creating a LOVE audio source.
class _LoveAudioSourceInput {
  /// Creates normalized metadata for constructing a LOVE audio source.
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

  /// The logical source identifier passed to the audio backend.
  final String source;

  /// The original filename when this input came from a resource-backed file.
  final String? filename;

  /// The LOVE source type used when the caller does not provide one.
  final String defaultSourceType;

  /// The only allowed LOVE source type when the input kind forces one.
  final String? fixedSourceType;

  /// In-memory audio bytes supplied directly to the backend, when available.
  final Uint8List? bytes;

  /// The detected MIME type for [bytes], when it can be inferred.
  final String? mimeType;

  /// The decoded audio duration in seconds, or a negative sentinel when unknown.
  final double durationSeconds;

  /// The decoded sample count, or a negative sentinel when unknown.
  final int durationSamples;

  /// The decoded sample rate in hertz, or zero when unknown.
  final int sampleRate;

  /// The decoded bits per sample, or zero when unknown.
  final int bitDepth;

  /// The decoded channel count used to configure playback.
  final int channelCount;
}

/// Best-effort decoded metadata extracted from file-backed audio input.
class _LoveDecodedAudioMetadata {
  const _LoveDecodedAudioMetadata({
    required this.durationSeconds,
    required this.durationSamples,
    required this.sampleRate,
    required this.bitDepth,
    required this.channelCount,
  });

  final double durationSeconds;
  final int durationSamples;
  final int sampleRate;
  final int bitDepth;
  final int channelCount;
}

/// Binds `love.audio.getActiveEffects`.
LoveApiImplementation _bindAudioGetActiveEffects(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) =>
      _audioStringListTable(runtime.audio.effects.activeEffectNames);
}

/// Binds `love.audio.getActiveSourceCount`.
LoveApiImplementation _bindAudioGetActiveSourceCount(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.audio.activeSourceCount;
}

/// Binds `love.audio.getDistanceModel`.
LoveApiImplementation _bindAudioGetDistanceModel(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.audio.distanceModel;
}

/// Binds `love.audio.getDopplerScale`.
LoveApiImplementation _bindAudioGetDopplerScale(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.audio.dopplerScale;
}

/// Binds `love.audio.getMaxSceneEffects`.
LoveApiImplementation _bindAudioGetMaxSceneEffects(
  LibraryRegistrationContext context,
) {
  return (args) => loveAudioMaxSceneEffects;
}

/// Binds `love.audio.getMaxSourceEffects`.
LoveApiImplementation _bindAudioGetMaxSourceEffects(
  LibraryRegistrationContext context,
) {
  return (args) => loveAudioMaxSourceEffects;
}

/// Binds `love.audio.getOrientation`.
///
/// The returned values match LOVE's `(fx, fy, fz, ux, uy, uz)` tuple.
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

/// Binds `love.audio.getPosition`.
LoveApiImplementation _bindAudioGetPosition(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final position = runtime.audio.position;
    return Value.multi(<Object?>[position.x, position.y, position.z]);
  };
}

/// Binds `love.audio.getRecordingDevices`.
LoveApiImplementation _bindAudioGetRecordingDevices(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) =>
      Value(_recordingDeviceTable(context, runtime.audio.recordingDevices));
}

/// Binds `love.audio.getVelocity`.
LoveApiImplementation _bindAudioGetVelocity(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final velocity = runtime.audio.velocity;
    return Value.multi(<Object?>[velocity.x, velocity.y, velocity.z]);
  };
}

/// Binds `love.audio.getVolume`.
LoveApiImplementation _bindAudioGetVolume(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.audio.volume;
}

/// Binds `love.audio.isEffectsSupported`.
///
/// The current backend always reports effects support for LOVE compatibility.
LoveApiImplementation _bindAudioIsEffectsSupported(
  LibraryRegistrationContext context,
) {
  return (args) => true;
}

/// Binds `love.audio.newSource`.
///
/// LOVE accepts `SoundData`, `Decoder`, or resource-backed file inputs here and
/// derives the appropriate source metadata before creating the runtime source.
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
        'Cannot create queueable sources using newSource. '
        'Use newQueueableSource instead.',
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

/// Binds `love.audio.newQueueableSource`.
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

/// Binds `love.audio.pause`.
///
/// When called without arguments, LOVE returns the list of paused sources. When
/// specific sources are passed, this returns `nil`.
LoveApiImplementation _bindAudioPause(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) async {
    final sources = _audioSourceSequence(args, 'love.audio.pause');
    final paused = await runtime.audio.pause(sources.isEmpty ? null : sources);
    return args.isEmpty ? Value(_audioSourceTable(context, paused)) : null;
  };
}

/// Binds `love.audio.play`.
LoveApiImplementation _bindAudioPlay(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) async {
    if (args.isEmpty) {
      _requireAudioSource(args, 0, 'love.audio.play');
    }

    return await runtime.audio.play(
      _audioSourceSequence(args, 'love.audio.play'),
    );
  };
}

/// Binds `love.audio.setDistanceModel`.
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

/// Binds `love.audio.setDopplerScale`.
LoveApiImplementation _bindAudioSetDopplerScale(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final scale = _requireNumber(args, 0, 'love.audio.setDopplerScale');
    if (scale >= 0.0) {
      runtime.audio.dopplerScale = scale;
    }
    return null;
  };
}

/// Binds `love.audio.setMixWithSystem`.
LoveApiImplementation _bindAudioSetMixWithSystem(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) async {
    final mix = _requireBoolean(args, 0, 'love.audio.setMixWithSystem');
    runtime.audio.mixWithSystem = mix;
    return await runtime.host.setAudioMixWithSystem(mix);
  };
}

/// Binds `love.audio.setOrientation`.
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

/// Binds `love.audio.setPosition`.
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

/// Binds `love.audio.setVelocity`.
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

/// Binds `love.audio.setVolume`.
LoveApiImplementation _bindAudioSetVolume(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.audio.volume = _requireNumber(args, 0, 'love.audio.setVolume');
    return null;
  };
}

/// Binds `love.audio.stop`.
LoveApiImplementation _bindAudioStop(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) async {
    await runtime.audio.stop(
      args.isEmpty ? null : _audioSourceSequence(args, 'love.audio.stop'),
    );
    return null;
  };
}

/// Returns the validated LOVE source type at [index].
String _requireAudioSourceType(List<Object?> args, int index, String symbol) {
  final value = _requireString(args, index, symbol);
  if (!loveAudioSourceTypes.contains(value)) {
    throw LuaError(
      _audioEnumErrorMessage('source type', loveAudioSourceTypes, value),
    );
  }
  return value;
}

/// Validates queueable-source PCM metadata.
void _validateAudioQueueMetadata({
  required int sampleRate,
  required int bitDepth,
  required int channels,
}) {
  if ((bitDepth != 8 && bitDepth != 16) || channels < 1 || channels > 2) {
    throw LuaError(
      '$channels-channel Sources with $bitDepth bits per sample are not supported.',
    );
  }
}

/// Returns the audio time unit at [index], defaulting to `seconds`.
String _audioTimeUnitAt(List<Object?> args, int index, String symbol) {
  if (args.length <= index || _rawValue(_valueAt(args, index)) == null) {
    return 'seconds';
  }

  final value = _requireString(args, index, symbol);
  if (!loveAudioTimeUnits.contains(value)) {
    throw LuaError(
      _audioEnumErrorMessage('time unit', loveAudioTimeUnits, value),
    );
  }
  return value;
}

/// Returns the validated LOVE audio distance model at [index].
String _requireAudioDistanceModel(
  List<Object?> args,
  int index,
  String symbol,
) {
  final value = _requireString(args, index, symbol);
  if (!loveAudioDistanceModels.contains(value)) {
    throw LuaError(
      _audioEnumErrorMessage('distance model', loveAudioDistanceModels, value),
    );
  }
  return value;
}

/// Binds `Source:play`.
LoveApiImplementation _bindSourcePlay(LibraryRegistrationContext context) {
  return (args) async {
    return await _requireAudioSource(args, 0, 'Source:play').play();
  };
}

/// Binds `Source:setLooping`.
///
/// Queueable sources cannot be looped in LOVE, so this binding rejects that
/// combination explicitly.
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

/// Binds `Source:queue`.
LoveApiImplementation _bindSourceQueue(LibraryRegistrationContext context) {
  return (args) => _queueSourceInput(args, 'Source:queue');
}

/// Resolves a LOVE audio source input into normalized source metadata.
///
/// This accepts `SoundData`, `Decoder`, or resource-backed file inputs and
/// returns the metadata needed to create a runtime audio source.
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

  final fileData = await (() async {
    final compat = _filesystemFileDataCompatIfPresent(sourceValue);
    if (compat != null) {
      return compat;
    }

    final filename = _stringLike(sourceValue);
    if (filename == null) {
      if (_soundFilesystemFileIfPresent(sourceValue) != null) {
        return _coerceResourceFileDataViaFilesystem(
          context,
          sourceValue,
          symbol,
        );
      }
      return null;
    }

    final mounted = await _readMountedResourceFileData(
      context,
      filename,
      symbol: symbol,
    );
    if (mounted != null) {
      return mounted;
    }

    throw _missingResourceFileError(filename);
  })();
  if (fileData == null) {
    throw LuaError(
      "bad argument #1 to 'newSource' "
      "(filename, File, FileData, Decoder, or SoundData expected, got ${_luaTypeName(sourceValue)})",
    );
  }

  final decodedMetadata = _tryDecodeAudioMetadata(
    bytes: fileData.bytes,
    source: fileData.filename,
  );

  return _LoveAudioSourceInput(
    source: fileData.filename,
    filename: fileData.filename,
    defaultSourceType: 'stream',
    bytes: Uint8List.fromList(fileData.bytes),
    mimeType: loveAudioMimeTypeFromFilename(fileData.filename),
    durationSeconds: decodedMetadata?.durationSeconds ?? -1.0,
    durationSamples: decodedMetadata?.durationSamples ?? -1,
    sampleRate: decodedMetadata?.sampleRate ?? 0,
    bitDepth: decodedMetadata?.bitDepth ?? 0,
    channelCount: decodedMetadata?.channelCount ?? 2,
  );
}

/// Returns decoded source metadata when the runtime can inspect [bytes].
_LoveDecodedAudioMetadata? _tryDecodeAudioMetadata({
  required List<int> bytes,
  required String source,
}) {
  try {
    final decoded = loveDecodeSoundFile(bytes: bytes, source: source);
    return _LoveDecodedAudioMetadata(
      durationSeconds: decoded.duration,
      durationSamples: decoded.sampleCount,
      sampleRate: decoded.sampleRate,
      bitDepth: decoded.bitDepth,
      channelCount: decoded.channels,
    );
  } on UnsupportedError {
    return null;
  } on ArgumentError {
    return null;
  }
}

/// Normalizes positional or table-based source arguments into a source list.
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
        _throwAudioSourceTableEntryError(entry, symbol);
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

String _audioFunctionName(String symbol) {
  final lastDot = symbol.lastIndexOf('.');
  return lastDot >= 0 ? symbol.substring(lastDot + 1) : symbol;
}

Never _throwAudioSourceTableEntryError(Object? entry, String symbol) {
  final wrapper = _audioSourceWrapperTableIfPresent(entry);
  if (wrapper != null && wrapper[_loveAudioSourceReleasedWrapperKey] == true) {
    throw LuaError('Cannot use object after it has been released.');
  }

  throw LuaError(
    "bad argument #-1 to '${_audioFunctionName(symbol)}' "
    "(Source expected, got ${_luaTypeName(entry)})",
  );
}

/// Returns the queued slice requested from [soundData].
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

/// Resolves the second `Source:queue` argument into queued sound data.
///
/// LOVE accepts either `SoundData` or light userdata pointing at PCM bytes.
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

  throw LuaError(
    "bad argument #2 to 'queue' "
    "(SoundData or lightuserdata expected, got ${_luaTypeName(_valueAt(args, 1))})",
  );
}

/// Queues [queued] on [source], translating argument errors into [LuaError].
Object _queueResolvedSoundData(LoveAudioSource source, LoveSoundData queued) {
  try {
    return source.queueSoundData(queued);
  } on ArgumentError catch (error) {
    throw LuaError(error.message.toString());
  }
}

/// Builds queued `SoundData` from light userdata PCM bytes.
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
  final frameByteSize = (bitDepth ~/ 8) * channels;
  if (frameByteSize > 0 && length % frameByteSize != 0) {
    throw LuaError(
      'Data length must be a multiple of sample size ($frameByteSize bytes).',
    );
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
