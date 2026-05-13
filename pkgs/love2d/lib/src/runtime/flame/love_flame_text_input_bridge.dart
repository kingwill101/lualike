import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../love_runtime.dart';
import 'love_flame_input.dart';

/// Bridges LOVE text input state to Flutter's platform text input system.
///
/// This adapter owns a [TextInputConnection] while the LOVE viewport is focused
/// and keyboard text input is enabled, then forwards editing updates back to
/// [LoveFlameInputAdapter].
class LoveFlameTextInputBridge with TextInputClient {
  /// Creates a bridge that synchronizes LOVE text input with Flutter IME state.
  LoveFlameTextInputBridge({
    required FocusNode focusNode,
    required LoveKeyboardState keyboard,
    required LoveFlameInputAdapter input,
    required BuildContext Function() contextProvider,
  }) : _focusNode = focusNode,
       _keyboard = keyboard,
       _input = input,
       _contextProvider = contextProvider;

  /// The focus node that determines whether text input should stay attached.
  final FocusNode _focusNode;

  /// The keyboard state that exposes LOVE text-input flags and bounds.
  final LoveKeyboardState _keyboard;

  /// The input adapter that receives platform editing updates.
  final LoveFlameInputAdapter _input;

  /// Supplies the viewport context used to position the platform text field.
  final BuildContext Function() _contextProvider;

  /// The active Flutter text input connection, if one is attached.
  TextInputConnection? _connection;

  /// Whether this bridge has been permanently shut down.
  bool _disposed = false;

  /// Synchronizes the platform text input connection with current LOVE state.
  ///
  /// When the viewport is focused and text input is enabled, this attaches the
  /// platform connection if needed and updates its editable bounds to match the
  /// current LOVE text input rectangle.
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

  /// Closes any active platform text input connection and marks this disposed.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _detach();
  }

  @override
  /// The latest editing value mirrored from the LOVE text input state.
  TextEditingValue get currentTextEditingValue =>
      _input.currentTextEditingValue;

  @override
  /// The current autofill scope.
  ///
  /// LOVE text input does not participate in Flutter autofill.
  AutofillScope? get currentAutofillScope => null;

  @override
  /// Applies a platform editing update to the LOVE text input adapter.
  void updateEditingValue(TextEditingValue value) {
    _input.handleTextEditingValue(value);
  }

  @override
  /// Handles a submitted text action.
  ///
  /// LOVE routes newline handling through the editing value itself, so no extra
  /// action dispatch is needed here.
  void performAction(TextInputAction action) {}

  @override
  /// Handles a private platform text command.
  ///
  /// LOVE does not consume private platform text input commands.
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  /// Handles a floating cursor update from the platform text system.
  ///
  /// LOVE does not expose floating cursor behavior, so this is ignored.
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  /// Shows the platform autocorrection prompt rectangle.
  ///
  /// Flutter manages autocorrection UI without extra LOVE integration.
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  /// Responds to the platform closing the active text input connection.
  void connectionClosed() {
    _connection = null;
    _input.endPlatformTextInputSession();
  }

  /// Returns an attached text input connection for the current viewport.
  ///
  /// This reuses the active connection when possible and otherwise opens a new
  /// multiline connection, initializes it with the current editing value, and
  /// starts the corresponding LOVE platform session.
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

  /// Closes the active platform text input connection, if present.
  void _detach() {
    final connection = _connection;
    if (connection != null && connection.attached) {
      connection.close();
    }
    _connection = null;
    _input.endPlatformTextInputSession();
  }

  /// The editable rectangle reported to Flutter for the current text input.
  ///
  /// When LOVE has not provided a text input area, this falls back to the full
  /// viewport size so the platform IME still has a valid target region.
  Rect _textInputRect(Size size) {
    final area = _keyboard.textInputArea;
    if (area == null) {
      return Offset.zero & size;
    }

    return Rect.fromLTWH(area.x, area.y, area.width, area.height);
  }
}
