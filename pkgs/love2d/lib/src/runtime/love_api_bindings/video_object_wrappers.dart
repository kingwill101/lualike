part of '../love_api_bindings.dart';

/// Marker stored in released `Video` wrapper tables.
const String _loveVideoReleasedWrapperKey = '__love2d_video_wrapper_released__';

/// Marker stored in released `VideoStream` wrapper tables.
const String _loveVideoStreamReleasedWrapperKey =
    '__love2d_video_stream_wrapper_released__';

/// Returns the Lua wrapper table for a `Video`, including released wrappers.
Map<dynamic, dynamic>? _videoWrapperTableIfPresent(Object? value) {
  final table = _tableIdentityIfPresent(value);
  if (table == null) {
    return null;
  }

  final video = table[_loveVideoObjectKey];
  if (video is LoveVideo || table[_loveVideoReleasedWrapperKey] == true) {
    return table;
  }

  return null;
}

/// Returns wrapped [LoveVideo] when [value] is a Video table.
LoveVideo? _videoIfPresent(Object? value) {
  final table = _videoWrapperTableIfPresent(value);
  if (table == null) {
    return null;
  }

  final video = table[_loveVideoObjectKey];
  if (video is! LoveVideo || table[_loveVideoReleasedWrapperKey] == true) {
    return null;
  }

  return video;
}

/// Returns whether [value] is a released `Video` wrapper.
bool _videoWrapperReleased(Object? value) {
  final table = _videoWrapperTableIfPresent(value);
  return table?[_loveVideoReleasedWrapperKey] == true;
}

/// Returns a required `Video` receiver.
LoveVideo _requireVideo(List<Object?> args, int index, String symbol) {
  final value = _valueAt(args, index);
  if (_videoWrapperReleased(value)) {
    _throwReleasedObjectError();
  }

  final video = _videoIfPresent(value);
  if (video != null) {
    return video;
  }

  _throwLuaStyleTypeError(
    symbol: symbol,
    index: index,
    expected: 'Video',
    actual: value,
  );
}

/// Wraps [video] as a Lua-facing `Video` object table.
Value _wrapVideo(LibraryRegistrationContext context, LoveVideo video) {
  final cached = _loveVideoWrapperCache[video];
  if (cached != null && _videoIfPresent(cached) != null) {
    return cached;
  }

  final runtime = _runtimeContext(context);
  final builder = BuiltinFunctionBuilder(context);
  final libraryContext = LibraryContext(
    environment: context.environment,
    interpreter: context.interpreter,
  );
  const hierarchy = <String>{'Video', 'Drawable', 'Object'};
  final table = ValueClass.table(<Object?, Object?>{
    _loveVideoObjectKey: video,
    'getDimensions': Value(
      builder.create((args) {
        final video = _requireVideo(args, 0, 'Video:getDimensions');
        return Value.multi(<Object?>[video.width, video.height]);
      }),
      functionName: 'getDimensions',
    ),
    'getFilter': Value(
      builder.create(
        (args) =>
            _filterResult(_requireVideo(args, 0, 'Video:getFilter').filter),
      ),
      functionName: 'getFilter',
    ),
    'getHeight': Value(
      builder.create(
        (args) => _requireVideo(args, 0, 'Video:getHeight').height,
      ),
      functionName: 'getHeight',
    ),
    'getPixelDimensions': Value(
      builder.create((args) {
        final video = _requireVideo(args, 0, 'Video:getPixelDimensions');
        return Value.multi(<Object?>[video.pixelWidth, video.pixelHeight]);
      }),
      functionName: 'getPixelDimensions',
    ),
    'getPixelHeight': Value(
      builder.create(
        (args) => _requireVideo(args, 0, 'Video:getPixelHeight').pixelHeight,
      ),
      functionName: 'getPixelHeight',
    ),
    'getPixelWidth': Value(
      builder.create(
        (args) => _requireVideo(args, 0, 'Video:getPixelWidth').pixelWidth,
      ),
      functionName: 'getPixelWidth',
    ),
    'getSource': Value(
      builder.create((args) {
        final source = _requireVideo(args, 0, 'Video:getSource').source;
        return source == null ? null : _wrapAudioSource(context, source);
      }),
      functionName: 'getSource',
    ),
    'getStream': Value(
      builder.create(
        (args) => _wrapVideoStream(
          libraryContext,
          _requireVideo(args, 0, 'Video:getStream').stream,
        ),
      ),
      functionName: 'getStream',
    ),
    'getWidth': Value(
      builder.create((args) => _requireVideo(args, 0, 'Video:getWidth').width),
      functionName: 'getWidth',
    ),
    'isPlaying': Value(
      builder.create(
        (args) => _requireVideo(args, 0, 'Video:isPlaying').isPlaying(),
      ),
      functionName: 'isPlaying',
    ),
    'pause': Value(
      builder.create((args) async {
        await _requireVideo(args, 0, 'Video:pause').pause();
        return null;
      }),
      functionName: 'pause',
    ),
    'play': Value(
      builder.create((args) async {
        await _requireVideo(args, 0, 'Video:play').play();
        return null;
      }),
      functionName: 'play',
    ),
    'rewind': Value(
      builder.create((args) async {
        await _requireVideo(args, 0, 'Video:rewind').rewind();
        return null;
      }),
      functionName: 'rewind',
    ),
    'seek': Value(
      builder.create((args) async {
        const symbol = 'Video:seek';
        final offset = _requireLuaStyleNumber(args, 1, symbol);
        await _requireVideo(args, 0, symbol).seek(offset);
        return null;
      }),
      functionName: 'seek',
    ),
    'setFilter': Value(
      builder.create((args) {
        final video = _requireVideo(args, 0, 'Video:setFilter');
        video.filter = _filterFromArgs(
          args,
          1,
          'Video:setFilter',
          currentFilter: video.filter,
        );
        return null;
      }),
      functionName: 'setFilter',
    ),
    '_setSource': Value(
      builder.create((args) {
        const symbol = 'Video:_setSource';
        final video = _requireVideo(args, 0, symbol);
        final sourceValue = _valueAt(args, 1);
        final source = sourceValue == null
            ? null
            : _audioSourceIfPresent(sourceValue);
        if (sourceValue != null && source == null) {
          throw LuaError(
            "bad argument #2 to '_setSource' "
            "(Source expected, got ${_luaTypeName(sourceValue)})",
          );
        }
        video.setRawSource(source);
        return null;
      }),
      functionName: '_setSource',
    ),
    'setSource': Value(
      builder.create((args) async {
        const symbol = 'Video:setSource';
        final video = _requireVideo(args, 0, symbol);
        final sourceValue = _valueAt(args, 1);
        final source = sourceValue == null
            ? null
            : _audioSourceIfPresent(sourceValue);
        if (sourceValue != null && source == null) {
          throw LuaError(
            "bad argument #2 to 'setSource' "
            "(Source expected, got ${_luaTypeName(sourceValue)})",
          );
        }
        await video.setSource(source);
        return null;
      }),
      functionName: 'setSource',
    ),
    'tell': Value(
      builder.create((args) => _requireVideo(args, 0, 'Video:tell').tell()),
      functionName: 'tell',
    ),
    'release': Value(
      builder.create((args) async {
        final receiver = _valueAt(args, 0);
        final table = _videoWrapperTableIfPresent(receiver);
        if (table == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:release',
            index: 0,
            expected: 'Video',
            actual: receiver,
          );
        }

        final video = table[_loveVideoObjectKey];
        if (video is! LoveVideo) {
          return false;
        }
        if (table[_loveVideoReleasedWrapperKey] == true) {
          return false;
        }
        table[_loveVideoReleasedWrapperKey] = true;
        table[_loveVideoObjectKey] = null;
        _releaseCachedDrawableImageForVideo(runtime, video);
        await video.dispose();
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_videoWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:type',
            index: 0,
            expected: 'Video',
            actual: receiver,
          );
        }
        return 'Video';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_videoWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:typeOf',
            index: 0,
            expected: 'Video',
            actual: receiver,
          );
        }
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });

  _loveVideoWrapperCache[video] = table;
  return table;
}

/// Returns the Lua wrapper table for a `VideoStream`, including released wrappers.
Map<dynamic, dynamic>? _videoStreamWrapperTableIfPresent(Object? value) {
  final table = _tableIdentityIfPresent(value);
  if (table == null) {
    return null;
  }

  final stream = table[_loveVideoStreamObjectKey];
  if (stream is LoveVideoStream ||
      table[_loveVideoStreamReleasedWrapperKey] == true) {
    return table;
  }

  return null;
}

/// Returns wrapped [LoveVideoStream] when [value] is a VideoStream table.
LoveVideoStream? _videoStreamIfPresent(Object? value) {
  final table = _videoStreamWrapperTableIfPresent(value);
  if (table == null) {
    return null;
  }

  final stream = table[_loveVideoStreamObjectKey];
  if (stream is! LoveVideoStream ||
      table[_loveVideoStreamReleasedWrapperKey] == true) {
    return null;
  }

  return stream;
}

/// Returns whether [value] is a released `VideoStream` wrapper.
bool _videoStreamWrapperReleased(Object? value) {
  final table = _videoStreamWrapperTableIfPresent(value);
  return table?[_loveVideoStreamReleasedWrapperKey] == true;
}

/// Returns a required `VideoStream` receiver.
LoveVideoStream _requireVideoStream(
  List<Object?> args,
  int index,
  String symbol,
) {
  final value = _valueAt(args, index);
  if (_videoStreamWrapperReleased(value)) {
    _throwReleasedObjectError();
  }

  final stream = _videoStreamIfPresent(value);
  if (stream != null) {
    return stream;
  }

  _throwLuaStyleTypeError(
    symbol: symbol,
    index: index,
    expected: 'VideoStream',
    actual: value,
  );
}

/// Wraps [stream] as a Lua-facing `VideoStream` object table.
Value _wrapVideoStream(LibraryContext context, LoveVideoStream stream) {
  final cached = _loveVideoStreamWrapperCache[stream];
  if (cached != null && _videoStreamIfPresent(cached) != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  const hierarchy = <String>{'VideoStream', 'Stream', 'Object'};
  final table = ValueClass.table(<Object?, Object?>{
    _loveVideoStreamObjectKey: stream,
    'getFilename': Value(
      builder.create(
        (args) =>
            _requireVideoStream(args, 0, 'VideoStream:getFilename').filename,
      ),
      functionName: 'getFilename',
    ),
    'isPlaying': Value(
      builder.create(
        (args) =>
            _requireVideoStream(args, 0, 'VideoStream:isPlaying').isPlaying(),
      ),
      functionName: 'isPlaying',
    ),
    'pause': Value(
      builder.create((args) async {
        await _requireVideoStream(args, 0, 'VideoStream:pause').pause();
        return null;
      }),
      functionName: 'pause',
    ),
    'play': Value(
      builder.create((args) async {
        await _requireVideoStream(args, 0, 'VideoStream:play').play();
        return null;
      }),
      functionName: 'play',
    ),
    'rewind': Value(
      builder.create((args) async {
        await _requireVideoStream(args, 0, 'VideoStream:rewind').rewind();
        return null;
      }),
      functionName: 'rewind',
    ),
    'seek': Value(
      builder.create((args) async {
        const symbol = 'VideoStream:seek';
        final stream = _requireVideoStream(args, 0, symbol);
        final offset = _requireLuaStyleNumber(args, 1, symbol);
        await stream.seek(offset);
        return null;
      }),
      functionName: 'seek',
    ),
    'setSync': Value(
      builder.create((args) async {
        const symbol = 'VideoStream:setSync';
        final stream = _requireVideoStream(args, 0, symbol);
        final syncTarget = _valueAt(args, 1);
        if (syncTarget == null) {
          await stream.setIndependentSync();
          return null;
        }

        final source = _audioSourceIfPresent(syncTarget);
        if (source != null) {
          stream.setSyncFromSource(source);
          return null;
        }

        final otherStream = _videoStreamIfPresent(syncTarget);
        if (otherStream != null) {
          stream.setSyncFromStream(otherStream);
          return null;
        }

        throw LuaError(
          "bad argument #2 to 'setSync' "
          "(Source or VideoStream or nil expected, got ${_luaTypeName(syncTarget)})",
        );
      }),
      functionName: 'setSync',
    ),
    'tell': Value(
      builder.create(
        (args) => _requireVideoStream(args, 0, 'VideoStream:tell').tell(),
      ),
      functionName: 'tell',
    ),
    'release': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        final table = _videoStreamWrapperTableIfPresent(receiver);
        if (table == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:release',
            index: 0,
            expected: 'VideoStream',
            actual: receiver,
          );
        }

        final stream = table[_loveVideoStreamObjectKey];
        if (stream is! LoveVideoStream) {
          return false;
        }
        if (table[_loveVideoStreamReleasedWrapperKey] == true) {
          return false;
        }
        table[_loveVideoStreamReleasedWrapperKey] = true;
        table[_loveVideoStreamObjectKey] = null;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_videoStreamWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:type',
            index: 0,
            expected: 'VideoStream',
            actual: receiver,
          );
        }
        return 'VideoStream';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_videoStreamWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:typeOf',
            index: 0,
            expected: 'VideoStream',
            actual: receiver,
          );
        }
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });

  _loveVideoStreamWrapperCache[stream] = table;
  return table;
}
