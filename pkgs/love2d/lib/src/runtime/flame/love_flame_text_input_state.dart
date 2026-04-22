import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../love_runtime.dart';
import '../love_script_runtime.dart';

typedef LoveFlameRuntimeDispatch =
    void Function(Future<Object?> Function(LoveScriptRuntime runtime) callback);

class LoveFlameTextInputState {
  LoveFlameTextInputState({
    required LoveKeyboardState keyboard,
    required LoveFlameRuntimeDispatch dispatch,
  }) : _keyboard = keyboard,
       _dispatch = dispatch;

  final LoveKeyboardState _keyboard;
  final LoveFlameRuntimeDispatch _dispatch;

  TextEditingValue _editingValue = TextEditingValue.empty;
  String _committedText = '';
  bool _platformSessionActive = false;

  TextEditingValue get editingValue => _editingValue;

  bool get platformSessionActive => _platformSessionActive;

  void beginPlatformSession() {
    _platformSessionActive = true;
    clear();
  }

  void endPlatformSession() {
    _platformSessionActive = false;
    clear();
  }

  void clear() {
    final previousCandidate = _candidateStateFor(_editingValue);
    _editingValue = TextEditingValue.empty;
    _committedText = '';
    if (!previousCandidate.isEmpty) {
      _dispatch((runtime) => runtime.queueTextEdited('', 0, 0));
    }
  }

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

final class _LoveFlameTextEditingCandidate {
  const _LoveFlameTextEditingCandidate({
    required this.text,
    required this.start,
    required this.length,
  });

  const _LoveFlameTextEditingCandidate.empty()
    : text = '',
      start = 0,
      length = 0;

  final String text;
  final int start;
  final int length;

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
