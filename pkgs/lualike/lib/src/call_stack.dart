import 'ast.dart';
import 'lua_stack_trace.dart';

/// Represents a call frame in the interpreter's call stack.
class CallFrame {
  /// The name of the function being called.
  final String functionName;

  /// The AST node representing the function call.
  final AstNode? callNode;

  /// The script path, if known
  final String? scriptPath;

  /// The most recent line number executed within this frame (1-based). -1 when unknown.
  int currentLine;

  /// Creates a new call frame with the given function name and call node.
  CallFrame(this.functionName, {this.callNode, this.scriptPath, this.currentLine = -1});

  /// Creates a LuaStackFrame from this call frame.
  LuaStackFrame toLuaStackFrame() {
    return callNode != null
        ? LuaStackFrame.fromNode(callNode!, functionName)
        : LuaStackFrame(functionName);
  }
}

/// Manages the call stack for the interpreter.
///
/// Tracks function calls and returns to maintain the call stack
/// for debugging and error reporting.
class CallStack {
  /// The frames in the call stack, from most recent to oldest.
  final List<CallFrame> _frames = [];

  /// The current script path, if known
  String? _scriptPath;

  /// Sets the current script path
  void setScriptPath(String? path) {
    _scriptPath = path;
  }

  /// Gets the current script path
  String? get scriptPath => _scriptPath;

  /// Pushes a new frame onto the call stack.
  void push(String functionName, {AstNode? callNode}) {
    _frames.add(
      CallFrame(functionName, callNode: callNode, scriptPath: _scriptPath),
    );
  }

  /// Pops the top frame from the call stack.
  CallFrame? pop() {
    return _frames.isNotEmpty ? _frames.removeLast() : null;
  }

  /// Returns the current call depth.
  int get depth => _frames.length;

  /// Returns the top frame of the call stack.
  CallFrame? get top => _frames.isNotEmpty ? _frames.last : null;

  /// Clears the call stack.
  void clear() {
    _frames.clear();
  }

  /// Creates a LuaStackTrace from the current call stack.
  LuaStackTrace toLuaStackTrace() {
    final frames = _frames.map((frame) => frame.toLuaStackFrame()).toList();
    // Reverse the frames to have most recent first
    return LuaStackTrace(frames.reversed.toList(), scriptPath: _scriptPath);
  }

  @override
  String toString() {
    return _frames.map((frame) => frame.functionName).join(' <- ');
  }

  /// Returns the top frame of the call stack (alias for top).
  /// Provided for backward compatibility.
  CallFrame? get current => top;

  /// Gets a frame at a specific level from the top of the stack.
  /// Level 1 is the top frame, level 2 is one below, etc.
  CallFrame? getFrameAtLevel(int level) {
    if (level <= 0 || level > _frames.length) {
      return null;
    }
    // Level 1 is the top frame (most recent)
    final frameIndex = _frames.length - level;
    return _frames[frameIndex];
  }
}
