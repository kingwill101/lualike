import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../love_runtime.dart';
import '../love_script_runtime.dart';

/// Dispatches a callback onto the active LOVE script runtime.
typedef LoveFlameRuntimeDispatch =
    void Function(Future<Object?> Function(LoveScriptRuntime runtime) callback);

/// Tracks Flutter text editing state for LOVE text input integration.
///
/// This keeps the latest [TextEditingValue], derives LOVE-style committed text
/// and composing candidates from it, and emits `textinput` and `textedited`
/// callbacks through [LoveFlameRuntimeDispatch].
class LoveFlameTextInputState {
  /// Creates text input state backed by [keyboard] and [dispatch].
  LoveFlameTextInputState({
    required LoveKeyboardState keyboard,
    required LoveFlameRuntimeDispatch dispatch,
  }) : _keyboard = keyboard,
       _dispatch = dispatch;

  /// The LOVE keyboard state that controls whether text input is enabled.
  final LoveKeyboardState _keyboard;

  /// The runtime dispatcher used for LOVE text input callbacks.
  final LoveFlameRuntimeDispatch _dispatch;

  /// The latest platform editing value received from Flutter.
  TextEditingValue _editingValue = TextEditingValue.empty;

  /// The committed portion of [_editingValue] with composing text removed.
  String _committedText = '';

  /// Whether a platform text input session is currently active.
  bool _platformSessionActive = false;

  /// The latest platform editing value mirrored into this state object.
  TextEditingValue get editingValue => _editingValue;

  /// Whether Flutter currently owns the active text input session.
  bool get platformSessionActive => _platformSessionActive;

  /// Starts a new platform text input session and clears prior state.
  void beginPlatformSession() {
    _platformSessionActive = true;
    clear();
  }

  /// Ends the active platform text input session and clears transient state.
  void endPlatformSession() {
    _platformSessionActive = false;
    clear();
  }

  /// Clears the current editing state and cancels any active composition.
  void clear() {
    final previousCandidate = _candidateStateFor(_editingValue);
    _editingValue = TextEditingValue.empty;
    _committedText = '';
    if (!previousCandidate.isEmpty) {
      _dispatch((runtime) => runtime.queueTextEdited('', 0, 0));
    }
  }

  /// Applies a platform editing update and emits LOVE text input callbacks.
  ///
  /// Composing-region changes are translated into `textedited` events, while
  /// newly committed text is emitted through `textinput`.
  void handleEditingValue(TextEditingValue value) {
    if (!_keyboard.textInputEnabled) {
      return;
    }

    final previousCandidate = _candidateStateFor(_editingValue);
    final previousCommittedText = _committedText;
    final nextCandidate = _candidateStateFor(value);
    final nextCommittedText = _committedTextFor(value);

    _editingValue = value;
    _committedText = nextCommittedText;

    if (previousCandidate != nextCandidate) {
      _dispatch(
        (runtime) => runtime.queueTextEdited(
          nextCandidate.text,
          nextCandidate.start,
          nextCandidate.length,
        ),
      );
    }

    final insertedText = _insertedText(
      previousCommittedText,
      nextCommittedText,
    );
    if (insertedText.isNotEmpty) {
      _dispatch((runtime) => runtime.queueTextInput(insertedText));
    }
  }

  /// The committed text for [value] with any composing range removed.
  String _committedTextFor(TextEditingValue value) {
    if (!value.isComposingRangeValid || value.composing.isCollapsed) {
      return value.text;
    }

    return value.text.replaceRange(
      value.composing.start,
      value.composing.end,
      '',
    );
  }

  /// Returns text inserted between [previousText] and [nextText].
  ///
  /// This trims the shared prefix and suffix so only newly committed content is
  /// forwarded to LOVE as a `textinput` event.
  String _insertedText(String previousText, String nextText) {
    if (previousText == nextText || nextText.isEmpty) {
      return '';
    }

    var prefixLength = 0;
    final maxPrefixLength = math.min(previousText.length, nextText.length);
    while (prefixLength < maxPrefixLength &&
        previousText.codeUnitAt(prefixLength) ==
            nextText.codeUnitAt(prefixLength)) {
      prefixLength++;
    }

    var previousSuffixIndex = previousText.length;
    var nextSuffixIndex = nextText.length;
    while (previousSuffixIndex > prefixLength &&
        nextSuffixIndex > prefixLength &&
        previousText.codeUnitAt(previousSuffixIndex - 1) ==
            nextText.codeUnitAt(nextSuffixIndex - 1)) {
      previousSuffixIndex--;
      nextSuffixIndex--;
    }

    if (nextSuffixIndex <= prefixLength) {
      return '';
    }

    return nextText.substring(prefixLength, nextSuffixIndex);
  }

  /// The current LOVE composing candidate derived from [value].
  _LoveFlameTextEditingCandidate _candidateStateFor(TextEditingValue value) {
    if (!value.isComposingRangeValid || value.composing.isCollapsed) {
      return const _LoveFlameTextEditingCandidate.empty();
    }

    final composing = value.composing;
    final selection = value.selection;
    final selectionStart = selection.isValid ? selection.start : composing.end;
    final selectionEnd = selection.isValid ? selection.end : selectionStart;
    final clampedStart = selectionStart.clamp(composing.start, composing.end);
    final clampedEnd = selectionEnd.clamp(composing.start, composing.end);

    return _LoveFlameTextEditingCandidate(
      text: value.text.substring(composing.start, composing.end),
      start: clampedStart - composing.start,
      length: clampedEnd - clampedStart,
    );
  }
}

/// The composing candidate state reported to LOVE through `textedited`.
final class _LoveFlameTextEditingCandidate {
  /// Creates a candidate with composing [text] and selection offsets.
  const _LoveFlameTextEditingCandidate({
    required this.text,
    required this.start,
    required this.length,
  });

  /// Creates an empty candidate with no active composition.
  const _LoveFlameTextEditingCandidate.empty()
    : text = '',
      start = 0,
      length = 0;

  /// The composing text currently shown by the platform IME.
  final String text;

  /// The selection start relative to [text].
  final int start;

  /// The selected composing span length relative to [text].
  final int length;

  /// Whether this candidate represents the absence of active composition.
  bool get isEmpty => text.isEmpty && start == 0 && length == 0;

  @override
  bool operator ==(Object other) {
    return other is _LoveFlameTextEditingCandidate &&
        other.text == text &&
        other.start == start &&
        other.length == length;
  }

  @override
  int get hashCode => Object.hash(text, start, length);
}
