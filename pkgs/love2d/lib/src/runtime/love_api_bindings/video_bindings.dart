part of '../love_api_bindings.dart';

/// LOVE-style error message when a video source file cannot be opened.
const String _loveVideoFileOpenErrorMessage =
    'File is not open and cannot be opened';

/// Returns a wrapped filesystem file object when [value] is the compatibility
/// table shape used by the LOVE bindings.
LoveFilesystemFile? _filesystemFileCompatIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final file = table[_loveFilesystemFileObjectKeyCompat];
  return file is LoveFilesystemFile ? file : null;
}

/// Resolves a LOVE video source argument into file data.
///
/// The video bindings accept either a filename-like string or a wrapped
/// filesystem `File` object.
Future<LoveFilesystemFileData> _requireVideoFilesystemSource(
  LibraryRegistrationContext context,
  Object? source,
  String symbol, {
  int argumentIndex = 1,
  String expectedKinds = 'filename or File',
}) async {
  final filename = _stringLike(source);
  if (filename != null) {
    final mounted = await _readMountedResourceFileData(
      context,
      filename,
      symbol: symbol,
    );
    if (mounted != null) {
      return mounted;
    }

    throw LuaError(_loveVideoFileOpenErrorMessage);
  }

  final file = _filesystemFileCompatIfPresent(source);
  if (file != null) {
    if (!file.isOpen) {
      try {
        final opened = await file.open('r');
        if (!opened) {
          throw LuaError(_loveVideoFileOpenErrorMessage);
        }
      } on StateError {
        throw LuaError(_loveVideoFileOpenErrorMessage);
      }
    }

    try {
      return LoveFilesystemFileData(
        bytes: await file.readBytes(),
        filename: file.filename,
      );
    } on StateError catch (error) {
      throw LuaError(error.message);
    }
  }

  throw LuaError('$symbol expected $expectedKinds at argument $argumentIndex');
}

/// Creates a validated encoded video stream from [fileData].
///
/// Decoder construction errors are translated into LOVE-style [LuaError]
/// exceptions with the standard invalid-video fallback message.
LoveVideoStream _newValidatedVideoStream(
  LoveFilesystemFileData fileData, {
  required String symbol,
}) {
  try {
    return LoveVideoStream.encoded(
      filename: fileData.filename,
      bytes: fileData.bytes,
    );
  } on ArgumentError catch (error) {
    final message = error.message;
    throw LuaError(
      message is String && message.isNotEmpty
          ? message
          : '$symbol $loveVideoInvalidFileMessage',
    );
  }
}

/// Binds `love.video.newVideoStream`.
///
/// LOVE accepts the same filename-or-`File` sources here as the graphics video
/// constructor, but returns the reusable `VideoStream` object directly.
LoveApiImplementation _bindVideoNewVideoStream(
  LibraryRegistrationContext context,
) {
  final libraryContext = LibraryContext(
    environment: context.environment,
    interpreter: context.interpreter,
  );

  return (args) async {
    const symbol = 'love.video.newVideoStream';
    final fileData = await _requireVideoFilesystemSource(
      context,
      _valueAt(args, 0),
      symbol,
      expectedKinds: 'filename or File',
    );

    return _wrapVideoStream(
      libraryContext,
      _newValidatedVideoStream(fileData, symbol: symbol),
    );
  };
}
