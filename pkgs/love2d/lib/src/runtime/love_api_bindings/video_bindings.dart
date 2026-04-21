part of '../love_api_bindings.dart';

LoveApiImplementation _bindVideoNewVideoStream(
  LibraryRegistrationContext context,
) {
  final libraryContext = LibraryContext(
    environment: context.environment,
    interpreter: context.interpreter,
  );

  return (args) async {
    const symbol = 'love.video.newVideoStream';
    if (args.isEmpty) {
      throw LuaError('$symbol expects at least 1 argument');
    }

    final fileData = await _requireResourceFileData(
      context,
      _valueAt(args, 0),
      symbol,
      expectedKinds: 'filename or File',
    );

    return _wrapVideoStream(
      libraryContext,
      LoveVideoStream(
        filename: fileData.filename,
        bytes: Uint8List.fromList(fileData.bytes),
      ),
    );
  };
}
