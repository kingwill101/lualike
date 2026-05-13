part of '../love_api_bindings.dart';

/// Binds `love.errorhandler`.
///
/// The returned closure implements the stock LÖVE-style error screen loop and
/// keeps processing quit, escape, and copy-to-clipboard interactions.
LoveApiImplementation _bindLoveErrorHandler(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  final interpreter = context.interpreter;
  if (interpreter == null) {
    throw StateError('No Lua runtime available for LOVE bindings');
  }

  final builder = BuiltinFunctionBuilder(context);
  return (args) async {
    final rawMessage = _rawValue(_valueAt(args, 0));
    final message = rawMessage?.toString() ?? 'nil';
    final canCopyToClipboard = _loveTableField(interpreter, 'system') != null;

    await _prepareLoveErrorHandler(runtime);

    final baseText = _formatLoveErrorHandlerText(
      message,
      canCopyToClipboard: canCopyToClipboard,
    );
    var displayText = baseText;

    final loop = builder.create((args) async {
      runtime.events.pump();
      while (true) {
        final event = runtime.events.poll();
        if (event == null) {
          break;
        }

        if (event.name == 'quit' || event.name == 'q') {
          return 1;
        }

        if (event.name == 'keypressed' || event.name == 'kp') {
          final key = event.arguments.isEmpty
              ? null
              : _rawValue(event.arguments.first)?.toString();
          if (key == 'escape') {
            return 1;
          }
          if (key == 'c' &&
              canCopyToClipboard &&
              runtime.keyboard.isDown(const <String>['lctrl', 'rctrl'])) {
            await runtime.system.setClipboardText(baseText);
            displayText = '$baseText\n\nCopied to clipboard!';
          }
        }

        if (event.name == 'touchpressed' && canCopyToClipboard) {
          await runtime.system.setClipboardText(baseText);
          displayText = '$baseText\n\nCopied to clipboard!';
        }
      }

      _drawLoveErrorHandlerFrame(runtime, displayText);

      if (_loveTableField(interpreter, 'timer') != null &&
          !runtime.host.usesExternalFrameLoop) {
        await runtime.sleep(0.1);
      }

      return null;
    });

    return Value(loop, functionName: 'errorhandler_i');
  };
}

/// Resets input, audio, and graphics state before showing the error screen.
Future<void> _prepareLoveErrorHandler(LoveRuntimeContext runtime) async {
  runtime.mouse.setVisible(true);
  runtime.mouse.grabbed = false;
  runtime.mouse.setRelativeMode(false);
  runtime.mouse.setCursor();

  for (final joystick in runtime.joysticks.connectedDevices) {
    joystick.stopVibration();
  }

  await runtime.audio.stop();

  runtime.graphics.reset();
  runtime.graphics.origin();
  runtime.graphics.color = LoveColor.white;
  await runtime.ensureCurrentGraphicsFont();
}

/// Formats the text rendered by the fallback error screen.
String _formatLoveErrorHandlerText(
  String message, {
  required bool canCopyToClipboard,
}) {
  final buffer = StringBuffer('Error\n\n');
  buffer.write(message);
  buffer.write('\n\nPress Escape to quit');
  if (canCopyToClipboard) {
    buffer.write('\nPress Ctrl+C or tap to copy this error');
  }
  return buffer.toString();
}

/// Draws one frame of the fallback error screen using the active graphics font.
void _drawLoveErrorHandlerFrame(LoveRuntimeContext runtime, String text) {
  const double padding = 70.0;
  const LoveColor background = LoveColor(89 / 255, 157 / 255, 220 / 255, 1.0);
  final width = math.max(
    runtime.windowMetrics.width.toDouble() - padding,
    padding,
  );

  runtime.graphics.clear(background);
  runtime.graphics.addCommand(
    LoveTextCommand(
      color: runtime.graphics.color,
      lineWidth: runtime.graphics.lineWidth,
      lineStyle: runtime.graphics.lineStyle,
      lineJoin: runtime.graphics.lineJoin,
      blendMode: runtime.graphics.blendMode,
      blendAlphaMode: runtime.graphics.blendAlphaMode,
      colorMask: runtime.graphics.colorMask,
      wireframe: runtime.graphics.wireframe,
      scissor: runtime.graphics.scissor,
      shader: runtime.graphics.shader,
      transform: runtime.graphics.copyTransform(),
      textTransform: Matrix4.identity(),
      font: runtime.graphics.font,
      spans: <LoveTextSpan>[LoveTextSpan(text: text)],
      x: padding,
      y: padding,
      limit: width,
      align: 'left',
    ),
  );
}
