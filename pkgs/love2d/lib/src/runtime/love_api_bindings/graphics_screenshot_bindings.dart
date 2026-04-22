part of '../love_api_bindings.dart';

Value? _captureScreenshotCallbackIfPresent(Object? value) {
  return switch (value) {
    final Value wrapped when wrapped.isCallable() => wrapped,
    final BuiltinFunction function => Value(function),
    final Function function => Value(function),
    _ => null,
  };
}

String _captureScreenshotFormatFromFilename(String filename, String symbol) {
  final forwardSlash = filename.lastIndexOf('/');
  final backwardSlash = filename.lastIndexOf(r'\');
  final separatorIndex = math.max(forwardSlash, backwardSlash);
  final dotIndex = filename.lastIndexOf('.');
  final extension = dotIndex > separatorIndex && dotIndex < filename.length - 1
      ? filename.substring(dotIndex + 1)
      : '';
  return _imageEncodeFormat(extension, symbol);
}

LoveApiImplementation _bindGraphicsCaptureScreenshot(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  final interpreter = context.interpreter;
  if (interpreter == null) {
    throw StateError(
      'No Lua runtime available for love.graphics.captureScreenshot',
    );
  }

  return (args) {
    const symbol = 'love.graphics.captureScreenshot';
    if (args.isEmpty) {
      throw LuaError(
        '$symbol expected a function, string, or Channel at argument 1',
      );
    }

    final target = _valueAt(args, 0);
    final callback = _captureScreenshotCallbackIfPresent(target);
    if (callback != null) {
      runtime.graphics.captureScreenshot((imageData) async {
        await interpreter.callFunction(
          callback,
          <Object?>[_wrapImageData(context, imageData)],
          debugName: symbol,
          debugNameWhat: 'function',
        );
      });
      return null;
    }

    final filename = _stringLike(target);
    if (filename != null) {
      final format = _captureScreenshotFormatFromFilename(filename, symbol);
      runtime.graphics.captureScreenshot((imageData) async {
        await _writeResourceBytesOrThrow(
          context,
          filename,
          imageData.encode(format),
          symbol: symbol,
        );
      });
      return null;
    }

    final channel = _channelIfPresent(target);
    if (channel != null) {
      runtime.graphics.captureScreenshot((imageData) {
        channel.push(imageData);
      });
      return null;
    }

    throw LuaError(
      '$symbol expected a function, string, or Channel at argument 1',
    );
  };
}
