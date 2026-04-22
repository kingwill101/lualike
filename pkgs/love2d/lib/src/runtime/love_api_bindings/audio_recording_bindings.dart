part of '../love_api_bindings.dart';

const String _loveRecordingDeviceReleasedWrapperKey =
    '__love2d_recording_device_released__';

final Expando<bool> _loveRecordingDeviceReleased = Expando<bool>(
  'love2dRecordingDeviceReleased',
);

Map<dynamic, dynamic>? _recordingDeviceWrapperTableIfPresent(Object? value) {
  final table = _tableIdentityIfPresent(value);
  if (table == null) {
    return null;
  }

  final device = table[_loveRecordingDeviceObjectKey];
  if (device is LoveRecordingDevice ||
      table[_loveRecordingDeviceReleasedWrapperKey] == true) {
    return table;
  }

  return null;
}

bool _recordingDeviceWrapperReleased(Object? value) {
  final table = _recordingDeviceWrapperTableIfPresent(value);
  return table?[_loveRecordingDeviceReleasedWrapperKey] == true;
}

/// Returns the wrapped [LoveRecordingDevice] stored in [value], if any.
LoveRecordingDevice? _recordingDeviceIfPresent(Object? value) {
  final raw = _rawValue(value);
  final table = switch (raw) {
    final Map<dynamic, dynamic> map => map,
    _ => null,
  };
  if (table == null) {
    return null;
  }

  final device = table[_loveRecordingDeviceObjectKey];
  return device is LoveRecordingDevice ? device : null;
}

/// Returns the recording device argument at [index] or throws a [LuaError].
LoveRecordingDevice _requireRecordingDevice(
  List<Object?> args,
  int index,
  String symbol,
) {
  final value = _valueAt(args, index);
  if (_recordingDeviceWrapperReleased(value)) {
    _throwReleasedObjectError();
  }

  final device = _recordingDeviceIfPresent(value);
  if (device != null) {
    return device;
  }

  _throwLuaStyleTypeError(
    symbol: symbol,
    index: index,
    expected: 'RecordingDevice',
    actual: value,
  );
}

/// Builds the LOVE array table returned for a recording-device list.
Map<Object?, Object?> _recordingDeviceTable(
  LibraryRegistrationContext context,
  Iterable<LoveRecordingDevice> devices,
) {
  final table = <Object?, Object?>{};
  var index = 1;
  for (final device in devices) {
    table[index++] = _wrapRecordingDevice(context, device);
  }
  return table;
}

/// Wraps [device] in the Lua-facing `RecordingDevice` object table.
Value _wrapRecordingDevice(
  LibraryRegistrationContext context,
  LoveRecordingDevice device,
) {
  final cached = _loveRecordingDeviceWrapperCache[device];
  if (cached != null && _recordingDeviceWrapperTableIfPresent(cached) != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  const hierarchy = <String>{'RecordingDevice', 'Object'};
  final table = ValueClass.table(<Object?, Object?>{
    _loveRecordingDeviceObjectKey: device,
    'getBitDepth': Value(
      builder.create(_bindRecordingDeviceGetBitDepth(context)),
      functionName: 'getBitDepth',
    ),
    'getChannelCount': Value(
      builder.create(_bindRecordingDeviceGetChannelCount(context)),
      functionName: 'getChannelCount',
    ),
    'getData': Value(
      builder.create(_bindRecordingDeviceGetData(context)),
      functionName: 'getData',
    ),
    'getName': Value(
      builder.create(_bindRecordingDeviceGetName(context)),
      functionName: 'getName',
    ),
    'getSampleCount': Value(
      builder.create(_bindRecordingDeviceGetSampleCount(context)),
      functionName: 'getSampleCount',
    ),
    'getSampleRate': Value(
      builder.create(_bindRecordingDeviceGetSampleRate(context)),
      functionName: 'getSampleRate',
    ),
    'isRecording': Value(
      builder.create(_bindRecordingDeviceIsRecording(context)),
      functionName: 'isRecording',
    ),
    'start': Value(
      builder.create(_bindRecordingDeviceStart(context)),
      functionName: 'start',
    ),
    'stop': Value(
      builder.create(_bindRecordingDeviceStop(context)),
      functionName: 'stop',
    ),
    'release': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        final table = _recordingDeviceWrapperTableIfPresent(receiver);
        if (table == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:release',
            index: 0,
            expected: 'RecordingDevice',
            actual: receiver,
          );
        }

        final device = table[_loveRecordingDeviceObjectKey];
        if (device is! LoveRecordingDevice) {
          return false;
        }
        if (_loveRecordingDeviceReleased[device] == true) {
          return false;
        }

        _loveRecordingDeviceReleased[device] = true;
        table[_loveRecordingDeviceReleasedWrapperKey] = true;
        table[_loveRecordingDeviceObjectKey] = null;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_recordingDeviceWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:type',
            index: 0,
            expected: 'RecordingDevice',
            actual: receiver,
          );
        }
        return 'RecordingDevice';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_recordingDeviceWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:typeOf',
            index: 0,
            expected: 'RecordingDevice',
            actual: receiver,
          );
        }
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });
  final wrapped = Value(table);
  _loveRecordingDeviceWrapperCache[device] = wrapped;
  return wrapped;
}

/// Binds `RecordingDevice:getBitDepth`.
LoveApiImplementation _bindRecordingDeviceGetBitDepth(
  LibraryRegistrationContext context,
) {
  return (args) =>
      _requireRecordingDevice(args, 0, 'RecordingDevice:getBitDepth').bitDepth;
}

/// Binds `RecordingDevice:getChannelCount`.
LoveApiImplementation _bindRecordingDeviceGetChannelCount(
  LibraryRegistrationContext context,
) {
  return (args) => _requireRecordingDevice(
    args,
    0,
    'RecordingDevice:getChannelCount',
  ).channelCount;
}

/// Binds `RecordingDevice:getData`.
///
/// This returns pending captured audio as `SoundData`, or `nil` when the device
/// has no buffered recording data available.
LoveApiImplementation _bindRecordingDeviceGetData(
  LibraryRegistrationContext context,
) {
  return (args) {
    final data = _requireRecordingDevice(
      args,
      0,
      'RecordingDevice:getData',
    ).getData();
    return data == null ? null : _wrapSoundData(context, data);
  };
}

/// Binds `RecordingDevice:getName`.
LoveApiImplementation _bindRecordingDeviceGetName(
  LibraryRegistrationContext context,
) {
  return (args) =>
      _requireRecordingDevice(args, 0, 'RecordingDevice:getName').name;
}

/// Binds `RecordingDevice:getSampleCount`.
LoveApiImplementation _bindRecordingDeviceGetSampleCount(
  LibraryRegistrationContext context,
) {
  return (args) => _requireRecordingDevice(
    args,
    0,
    'RecordingDevice:getSampleCount',
  ).sampleCount;
}

/// Binds `RecordingDevice:getSampleRate`.
LoveApiImplementation _bindRecordingDeviceGetSampleRate(
  LibraryRegistrationContext context,
) {
  return (args) => _requireRecordingDevice(
    args,
    0,
    'RecordingDevice:getSampleRate',
  ).sampleRate;
}

/// Binds `RecordingDevice:isRecording`.
LoveApiImplementation _bindRecordingDeviceIsRecording(
  LibraryRegistrationContext context,
) {
  return (args) =>
      _requireRecordingDevice(args, 0, 'RecordingDevice:isRecording').recording;
}

/// Binds `RecordingDevice:start`.
///
/// When Lua omits the optional format arguments, this starts capture using the
/// device defaults or current negotiated settings.
LoveApiImplementation _bindRecordingDeviceStart(
  LibraryRegistrationContext context,
) {
  return (args) {
    const symbol = 'RecordingDevice:start';
    final device = _requireRecordingDevice(args, 0, symbol);
    var samples = device.maxSamples;
    var sampleRate = device.sampleRate;
    var bitDepth = device.bitDepth;
    var channels = device.channelCount;

    if (args.length > 1) {
      samples = _requireRoundedInt(args, 1, symbol);
      sampleRate = args.length >= 3
          ? _requireRoundedInt(args, 2, symbol)
          : LoveRecordingDevice.defaultSampleRate;
      bitDepth = args.length >= 4
          ? _requireRoundedInt(args, 3, symbol)
          : LoveRecordingDevice.defaultBitDepth;
      channels = args.length >= 5
          ? _requireRoundedInt(args, 4, symbol)
          : LoveRecordingDevice.defaultChannels;
    }

    try {
      return device.start(
        samples: samples,
        sampleRate: sampleRate,
        bitDepth: bitDepth,
        channels: channels,
      );
    } on ArgumentError catch (error) {
      throw LuaError(error.message.toString());
    }
  };
}

/// Binds `RecordingDevice:stop`.
///
/// LOVE returns the final captured `SoundData` when stopping succeeds, or `nil`
/// if no data was recorded.
LoveApiImplementation _bindRecordingDeviceStop(
  LibraryRegistrationContext context,
) {
  return (args) {
    final device = _requireRecordingDevice(args, 0, 'RecordingDevice:stop');
    final data = device.getData();
    device.stop();
    return data == null ? null : _wrapSoundData(context, data);
  };
}
