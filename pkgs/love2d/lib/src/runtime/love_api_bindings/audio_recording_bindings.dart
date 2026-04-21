part of '../love_api_bindings.dart';

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

LoveRecordingDevice _requireRecordingDevice(
  List<Object?> args,
  int index,
  String symbol,
) {
  final device = _recordingDeviceIfPresent(_valueAt(args, index));
  if (device != null) {
    return device;
  }

  throw LuaError('$symbol expected a RecordingDevice at argument ${index + 1}');
}

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

Value _wrapRecordingDevice(
  LibraryRegistrationContext context,
  LoveRecordingDevice device,
) {
  final cached = _loveRecordingDeviceWrapperCache[device];
  if (cached != null) {
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
    'type': Value(
      builder.create((args) => 'RecordingDevice'),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        final queried = _requireString(args, 1, 'RecordingDevice:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });
  final wrapped = Value(table);
  _loveRecordingDeviceWrapperCache[device] = wrapped;
  return wrapped;
}

LoveApiImplementation _bindRecordingDeviceGetBitDepth(
  LibraryRegistrationContext context,
) {
  return (args) =>
      _requireRecordingDevice(args, 0, 'RecordingDevice:getBitDepth').bitDepth;
}

LoveApiImplementation _bindRecordingDeviceGetChannelCount(
  LibraryRegistrationContext context,
) {
  return (args) => _requireRecordingDevice(
    args,
    0,
    'RecordingDevice:getChannelCount',
  ).channelCount;
}

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

LoveApiImplementation _bindRecordingDeviceGetName(
  LibraryRegistrationContext context,
) {
  return (args) =>
      _requireRecordingDevice(args, 0, 'RecordingDevice:getName').name;
}

LoveApiImplementation _bindRecordingDeviceGetSampleCount(
  LibraryRegistrationContext context,
) {
  return (args) => _requireRecordingDevice(
    args,
    0,
    'RecordingDevice:getSampleCount',
  ).sampleCount;
}

LoveApiImplementation _bindRecordingDeviceGetSampleRate(
  LibraryRegistrationContext context,
) {
  return (args) => _requireRecordingDevice(
    args,
    0,
    'RecordingDevice:getSampleRate',
  ).sampleRate;
}

LoveApiImplementation _bindRecordingDeviceIsRecording(
  LibraryRegistrationContext context,
) {
  return (args) =>
      _requireRecordingDevice(args, 0, 'RecordingDevice:isRecording').recording;
}

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

    return device.start(
      samples: samples,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      channels: channels,
    );
  };
}

LoveApiImplementation _bindRecordingDeviceStop(
  LibraryRegistrationContext context,
) {
  return (args) {
    final data = _requireRecordingDevice(
      args,
      0,
      'RecordingDevice:stop',
    ).stop();
    return data == null ? null : _wrapSoundData(context, data);
  };
}
