import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../love_runtime.dart';
import 'love_flame_input.dart';

class LoveFlameTextInputBridge with TextInputClient {
  LoveFlameTextInputBridge({
    required FocusNode focusNode,
    required LoveKeyboardState keyboard,
    required LoveFlameInputAdapter input,
    required BuildContext Function() contextProvider,
  }) : _focusNode = focusNode,
       _keyboard = keyboard,
       _input = input,
       _contextProvider = contextProvider;

  final FocusNode _focusNode;
  final LoveKeyboardState _keyboard;
  final LoveFlameInputAdapter _input;
  final BuildContext Function() _contextProvider;

  TextInputConnection? _connection;
  bool _disposed = false;

  void sync() {
    if (_disposed) {
      return;
    }

    if (!_focusNode.hasFocus || !_keyboard.textInputEnabled) {
      _detach();
      return;
    }

    final connection = _ensureConnection();
    if (!connection.attached) {
      return;
    }

    final context = _contextProvider();
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }

    connection.setEditableSizeAndTransform(
      renderObject.size,
      renderObject.getTransformTo(null),
    );
    connection.setComposingRect(_textInputRect(renderObject.size));
  }

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _detach();
  }

  @override
  TextEditingValue get currentTextEditingValue =>
      _input.currentTextEditingValue;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    _input.handleTextEditingValue(value);
  }

  @override
  void performAction(TextInputAction action) {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _connection = null;
    _input.endPlatformTextInputSession();
  }

  TextInputConnection _ensureConnection() {
    final existingConnection = _connection;
    if (existingConnection != null && existingConnection.attached) {
      return existingConnection;
    }

    final configuration = TextInputConfiguration(
      viewId: View.of(_contextProvider()).viewId,
      inputType: TextInputType.multiline,
      inputAction: TextInputAction.newline,
      autocorrect: true,
      enableSuggestions: true,
      textCapitalization: TextCapitalization.none,
      enableIMEPersonalizedLearning: true,
    );
    final connection = TextInput.attach(this, configuration);
    _connection = connection;
    _input.beginPlatformTextInputSession();
    connection.setEditingState(currentTextEditingValue);
    connection.show();
    return connection;
  }

  void _detach() {
    final connection = _connection;
    if (connection != null && connection.attached) {
      connection.close();
    }
    _connection = null;
    _input.endPlatformTextInputSession();
  }

  Rect _textInputRect(Size size) {
    final area = _keyboard.textInputArea;
    if (area == null) {
      return Offset.zero & size;
    }

    return Rect.fromLTWH(area.x, area.y, area.width, area.height);
  }
}
