part of '../love_api_bindings.dart';

LoveVideo? _videoIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final video = table[_loveVideoObjectKey];
  return video is LoveVideo ? video : null;
}

LoveVideo _requireVideo(List<Object?> args, int index, String symbol) {
  final video = _videoIfPresent(_valueAt(args, index));
  if (video != null) {
    return video;
  }

  throw LuaError('$symbol expected a Video at argument ${index + 1}');
}

Value _wrapVideo(LibraryRegistrationContext context, LoveVideo video) {
  final cached = _loveVideoWrapperCache[video];
  if (cached != null) {
    return cached;
  }

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
        final offset = _requireNumber(args, 1, symbol);
        if (offset < 0.0) {
          throw LuaError("can't seek to a negative position");
        }
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
    'setSource': Value(
      builder.create((args) async {
        const symbol = 'Video:setSource';
        final video = _requireVideo(args, 0, symbol);
        final sourceValue = _valueAt(args, 1);
        final source = sourceValue == null
            ? null
            : _audioSourceIfPresent(sourceValue);
        if (sourceValue != null && source == null) {
          throw LuaError('$symbol expected a Source or nil at argument 2');
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
      builder.create((args) {
        final video = _requireVideo(args, 0, 'Object:release');
        if (_loveVideoReleased[video] == true) {
          return false;
        }
        _loveVideoReleased[video] = true;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      builder.create((args) {
        _requireVideo(args, 0, 'Object:type');
        return 'Video';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        _requireVideo(args, 0, 'Object:typeOf');
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });

  _loveVideoWrapperCache[video] = table;
  return table;
}

LoveVideoStream? _videoStreamIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final stream = table[_loveVideoStreamObjectKey];
  return stream is LoveVideoStream ? stream : null;
}

LoveVideoStream _requireVideoStream(
  List<Object?> args,
  int index,
  String symbol,
) {
  final stream = _videoStreamIfPresent(_valueAt(args, index));
  if (stream != null) {
    return stream;
  }

  throw LuaError('$symbol expected a VideoStream at argument ${index + 1}');
}

Value _wrapVideoStream(LibraryContext context, LoveVideoStream stream) {
  final cached = _loveVideoStreamWrapperCache[stream];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  const hierarchy = <String>{'VideoStream', 'Object'};
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
        final offset = _requireNumber(args, 1, symbol);
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
          '$symbol expected a Source, VideoStream, or nil at argument 2',
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
        final stream = _requireVideoStream(args, 0, 'Object:release');
        if (_loveVideoStreamReleased[stream] == true) {
          return false;
        }
        _loveVideoStreamReleased[stream] = true;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      builder.create((args) {
        _requireVideoStream(args, 0, 'Object:type');
        return 'VideoStream';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        _requireVideoStream(args, 0, 'Object:typeOf');
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });

  _loveVideoStreamWrapperCache[stream] = table;
  return table;
}
