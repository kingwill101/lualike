part of '../love_api_bindings.dart';

/// Returns a callable screenshot callback wrapper for [value], if possible.
///
/// LOVE accepts plain Lua callables and some host-side callable wrappers here,
/// so this helper normalizes them into a [Value].
Value? _captureScreenshotCallbackIfPresent(Object? value) {
  return switch (value) {
    final Value wrapped when wrapped.isCallable() => wrapped,
    final BuiltinFunction function => Value(function),
    final Function function => Value(function),
    _ => null,
  };
}

/// Infers the screenshot encode format from [filename].
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

/// Binds `love.graphics.captureScreenshot`.
///
/// LOVE allows screenshots to be delivered to a callback, written to a file, or
/// pushed into a channel, so this binding dispatches based on the argument
/// shape and arranges the corresponding async host callback.
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
