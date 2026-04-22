part of '../love_api_bindings.dart';

typedef _LoveGraphicsVideoInput = ({
  LoveVideoStream stream,
  String source,
  Uint8List? bytes,
});

LoveApiImplementation _bindGraphicsNewVideo(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);

  return (args) async {
    const symbol = 'love.graphics.newVideo';
    if (args.isEmpty) {
      throw LuaError('$symbol expects at least 1 argument');
    }

    final input = await _resolveGraphicsVideoInput(
      context,
      _valueAt(args, 0),
      symbol,
    );
    final rawOptions = _rawValue(_valueAt(args, 1));

    Map<dynamic, dynamic>? settings;
    var shouldAttemptAudio = true;
    var audioMustSucceed = false;

    if (rawOptions == null) {
      // Default LOVE behavior is to attempt loading audio when possible.
    } else if (rawOptions is bool) {
      shouldAttemptAudio = rawOptions;
      audioMustSucceed = rawOptions;
    } else if (rawOptions is Map<dynamic, dynamic>) {
      settings = rawOptions;
      final audioSetting = _tableBool(rawOptions, 'audio');
      shouldAttemptAudio = audioSetting != false;
      audioMustSucceed = audioSetting == true;
    } else {
      throw LuaError('bad argument #2 to newVideo (expected boolean or table)');
    }

    final dpiScale = settings == null
        ? runtime.windowMetrics.dpiScale
        : (_numberIfPresent(_tableEntry(settings, 'dpiscale')) ??
              runtime.windowMetrics.dpiScale);
    if (dpiScale <= 0) {
      throw LuaError('$symbol dpiscale must be > 0');
    }

    final video = LoveVideo(
      stream: input.stream,
      dpiScale: dpiScale,
      filter: runtime.graphics.defaultFilter,
    );

    if (shouldAttemptAudio) {
      try {
        await video.setSource(
          await _newGraphicsVideoAudioSource(
            runtime,
            source: input.source,
            bytes: input.bytes,
          ),
        );
      } on Exception {
        if (audioMustSucceed) {
          throw LuaError('Video had no audio track');
        }
      }
    }

    return _wrapVideo(context, video);
  };
}

Future<_LoveGraphicsVideoInput> _resolveGraphicsVideoInput(
  LibraryRegistrationContext context,
  Object? sourceValue,
  String symbol,
) async {
  final stream = _videoStreamIfPresent(sourceValue);
  if (stream != null) {
    return (stream: stream, source: stream.filename, bytes: stream.bytes);
  }

  final fileData = await _requireResourceFileData(
    context,
    sourceValue,
    symbol,
    expectedKinds: 'filename, VideoStream, FileData, or File',
  );
  final bytes = Uint8List.fromList(fileData.bytes);
  return (
    stream: LoveVideoStream(filename: fileData.filename, bytes: bytes),
    source: fileData.filename,
    bytes: bytes,
  );
}

Future<LoveAudioSource> _newGraphicsVideoAudioSource(
  LoveRuntimeContext runtime, {
  required String source,
  Uint8List? bytes,
}) async {
  final mimeType = loveAudioMimeTypeFromFilename(source);
  return runtime.audio.newSource(
    sourceType: 'stream',
    source: source,
    filename: source,
    backend: await runtime.host.createAudioSourceBackend(
      source,
      sourceType: 'stream',
      bytes: bytes,
      mimeType: mimeType,
    ),
    bytes: bytes,
    mimeType: mimeType,
  );
}
