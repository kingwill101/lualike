part of '../love_api_bindings.dart';

/// Returns the current `love.audio` module table when it is available.
Map<dynamic, dynamic>? _audioModuleTableForContext(
  LibraryRegistrationContext context,
) {
  final loveTable = _tableIfPresent(context.environment.get('love'));
  if (loveTable == null) {
    return null;
  }

  return _tableIfPresent(loveTable['audio']);
}

/// The resolved source data used to construct a LOVE graphics video.
typedef _LoveGraphicsVideoInput = ({
  LoveVideoStream stream,
  String source,
  Uint8List? bytes,
});

/// Binds `love.graphics.newVideo`.
///
/// LOVE accepts `nil` or a settings table as the second argument, mirroring
/// the vendored `wrap_Graphics.lua` helper before constructing the runtime
/// [LoveVideo].
LoveApiImplementation _bindGraphicsNewVideo(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);

  return (args) async {
    const symbol = 'love.graphics.newVideo';
    final input = await _resolveGraphicsVideoInput(
      context,
      _valueAt(args, 0),
      symbol,
    );
    final rawOptions = _rawValue(_valueAt(args, 1));

    Map<dynamic, dynamic>? settings;
    var shouldAttemptAudio = true;
    var audioMustSucceed = false;
    var preserveExistingStreamSync = false;

    if (rawOptions == null) {
      // Default LOVE behavior is to attempt loading audio when possible.
    } else if (rawOptions is Map<dynamic, dynamic>) {
      settings = rawOptions;
      final rawAudioSetting = _rawValue(_tableEntry(rawOptions, 'audio'));
      shouldAttemptAudio = rawAudioSetting != false;
      audioMustSucceed = rawAudioSetting == true;
      preserveExistingStreamSync =
          _rawValue(_tableEntry(rawOptions, '__love2dPreserveStreamSync')) ==
          true;
    } else {
      throw LuaError('bad argument #2 to newVideo (expected table)');
    }

    final rawDpiScaleValue = settings == null
        ? null
        : _rawValue(_tableEntry(settings, 'dpiscale'));
    final dpiScale = switch (rawDpiScaleValue) {
      null => 1.0,
      final num value => value.toDouble(),
      final Object? raw => throw LuaError(
        "bad argument #2 to '_newVideo' "
        "(number expected, got ${NumberUtils.typeName(raw)})",
      ),
    };

    final frameProvider = await _createGraphicsVideoFrameProvider(
      runtime,
      source: input.source,
      bytes: input.bytes,
      metadata: input.stream.metadata,
    );
    final video = LoveVideo(
      stream: input.stream,
      dpiScale: dpiScale,
      filter: runtime.graphics.defaultFilter,
      frameProvider: frameProvider,
    );

    if (!shouldAttemptAudio) {
      if (!preserveExistingStreamSync) {
        await input.stream.setIndependentSync();
      }
      return _wrapVideo(context, video);
    }

    if (_audioModuleTableForContext(context) == null) {
      if (audioMustSucceed) {
        throw LuaError('love.audio was not loaded');
      }

      await input.stream.setIndependentSync();
      return _wrapVideo(context, video);
    }

    if (!input.stream.hasAudioTrack) {
      if (audioMustSucceed) {
        throw LuaError('Video had no audio track');
      }

      await input.stream.setIndependentSync();
      return _wrapVideo(context, video);
    }

    try {
      await video.setSource(
        await _newGraphicsVideoAudioSource(
          runtime,
          source: input.source,
          bytes: input.bytes,
        ),
      );
    } catch (_) {
      if (audioMustSucceed) {
        throw LuaError('Video had no audio track');
      }

      await input.stream.setIndependentSync();
    }

    return _wrapVideo(context, video);
  };
}

/// Creates a video frame provider through the active host integration.
Future<LoveVideoFrameProvider?> _createGraphicsVideoFrameProvider(
  LoveRuntimeContext runtime, {
  required String source,
  Uint8List? bytes,
  LoveVideoMetadata? metadata,
}) async {
  try {
    return await runtime.host.createVideoFrameProvider(
      source,
      bytes: bytes,
      metadata: metadata,
    );
  } on LuaError {
    rethrow;
  } catch (error) {
    throw LuaError(_graphicsVideoFrameProviderErrorMessage(error));
  }
}

/// Converts provider-construction failures into LOVE-facing error text.
String _graphicsVideoFrameProviderErrorMessage(Object error) {
  final message = error.toString();
  if (message.contains('Cannot find libmpv')) {
    return 'Video playback on Flutter/Linux currently requires libmpv for media_kit. '
        'Install libmpv-dev and restart the app. Original error: $message';
  }

  return 'Could not initialize video playback support: $message';
}

/// Resolves a video source argument into stream metadata and raw bytes.
///
/// The binding accepts either an existing `VideoStream` wrapper or the same
/// filename/File inputs accepted by `love.video.newVideoStream`.
Future<_LoveGraphicsVideoInput> _resolveGraphicsVideoInput(
  LibraryRegistrationContext context,
  Object? sourceValue,
  String symbol,
) async {
  final existingStream = _videoStreamIfPresent(sourceValue);
  if (existingStream != null) {
    return (
      stream: existingStream,
      source: existingStream.filename,
      bytes: existingStream.bytes,
    );
  }

  final fileData = await _requireVideoFilesystemSource(
    context,
    sourceValue,
    symbol,
    expectedKinds: 'filename, VideoStream, or File',
  );
  final createdStream = _newValidatedVideoStream(fileData, symbol: symbol);
  return (
    stream: createdStream,
    source: fileData.filename,
    bytes: createdStream.bytes,
  );
}

/// Creates the streaming audio source used by [LoveVideo] when audio is
/// available.
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
