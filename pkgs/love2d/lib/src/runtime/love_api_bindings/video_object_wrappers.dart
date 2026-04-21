part of '../love_api_bindings.dart';

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
        (args) => _requireVideoStream(
          args,
          0,
          'VideoStream:getFilename',
        ).filename,
      ),
      functionName: 'getFilename',
    ),
    'isPlaying': Value(
      builder.create(
        (args) => _requireVideoStream(
          args,
          0,
          'VideoStream:isPlaying',
        ).isPlaying(),
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
