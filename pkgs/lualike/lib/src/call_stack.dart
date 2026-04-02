import 'package:source_span/source_span.dart';

import 'ast.dart';
import 'lua_stack_trace.dart';
import 'environment.dart';
import 'value.dart';

/// Represents a call frame in the interpreter's call stack.
class CallFrame {
  /// The name of the function being called.
  String functionName;

  /// The AST node representing the function call.
  AstNode? callNode;

  /// The script path, if known
  String? scriptPath;

  /// The most recent line number executed within this frame (1-based). -1 when unknown.
  int currentLine;

  /// The environment active for this frame (if any)
  Environment? env;

  /// Cached debug name metadata captured at call time.
  String? debugName;
  String debugNameWhat;

  /// The callable associated with this frame when available.
  Value? callable;

  /// Most recent line reported to a line hook for this frame.
  int lastDebugHookLine;

  /// Debug locals for this frame, in enumeration order (1-based for Lua)
  /// Each entry stores the visible name and the underlying Value
  final List<MapEntry<String, Value>> debugLocals;
  Object? debugLocalsOwner;
  int debugLocalsPc;
  int debugLocalsVersion;

  /// Transfer metadata used by Lua 5.5 call/return hooks.
  int ftransfer;
  int ntransfer;
  List<Value> transferValues;

  /// Number of hidden extra arguments introduced by __call metamethod hops.
  int extraArgs;

  /// Whether this frame is executing a debug hook callback.
  bool isDebugHook;

  /// Whether this frame was entered via a tail call.
  bool isTailCall;

  /// Engine-specific execution state associated with this call frame.
  ///
  /// The AST interpreter leaves this unset. The bytecode VM uses it to keep
  /// the live register frame attached even when coroutine machinery snapshots
  /// and restores [CallFrame] objects.
  Object? engineFrameState;

  /// Creates a new call frame with the given function name and call node.
  CallFrame(
    this.functionName, {
    this.callNode,
    this.scriptPath,
    this.currentLine = -1,
    this.env,
    this.debugName,
    this.debugNameWhat = '',
    this.callable,
    this.lastDebugHookLine = -1,
    List<MapEntry<String, Value>>? debugLocals,
    this.debugLocalsOwner,
    this.debugLocalsPc = -1,
    this.debugLocalsVersion = -1,
    this.ftransfer = 0,
    this.ntransfer = 0,
    List<Value>? transferValues,
    this.extraArgs = 0,
    this.isDebugHook = false,
    this.isTailCall = false,
    this.engineFrameState,
  }) : debugLocals = debugLocals ?? <MapEntry<String, Value>>[],
       transferValues = transferValues ?? <Value>[];

  /// Creates a LuaStackFrame from this call frame.
  LuaStackFrame toLuaStackFrame() {
    if (callNode != null) {
      return LuaStackFrame.fromNode(
        callNode!,
        functionName,
        scriptPath: scriptPath,
      );
    }
    if (scriptPath != null && currentLine > 0) {
      final uri = Uri.file(scriptPath!);
      final location = SourceLocation(
        0,
        sourceUrl: uri,
        line: currentLine - 1,
        column: 0,
      );
      final span = SourceSpan(location, location, '');
      return LuaStackFrame(functionName, span: span, scriptPath: scriptPath);
    }
    return LuaStackFrame(functionName, scriptPath: scriptPath);
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
  void push(
    String functionName, {
    AstNode? callNode,
    Environment? env,
    String? debugName,
    String debugNameWhat = '',
    Value? callable,
  }) {
    _frames.add(
      CallFrame(
        functionName,
        callNode: callNode,
        scriptPath: _scriptPath,
        env: env,
        debugName: debugName,
        debugNameWhat: debugNameWhat,
        callable: callable,
      ),
    );
  }

  /// Restores a previously captured frame onto the stack.
  void pushFrame(CallFrame frame) {
    _frames.add(frame);
  }

  /// Pops the top frame from the call stack.
  CallFrame? pop() {
    return _frames.isNotEmpty ? _frames.removeLast() : null;
  }

  /// Removes a specific frame from the stack by identity.
  bool removeFrame(CallFrame frame) {
    for (var i = _frames.length - 1; i >= 0; i--) {
      if (identical(_frames[i], frame)) {
        _frames.removeAt(i);
        return true;
      }
    }
    return false;
  }

  /// Returns the current call depth.
  int get depth => _frames.length;

  /// Returns the top frame of the call stack.
  CallFrame? get top => _frames.isNotEmpty ? _frames.last : null;

  /// Exposes the current frames without allowing external mutation.
  Iterable<CallFrame> get frames => List.unmodifiable(_frames);

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

  /// Creates a LuaStackTrace from a suffix of the current call stack.
  /// [baseDepth] is the number of oldest frames to skip.
  LuaStackTrace toLuaStackTraceFromDepth(int baseDepth) {
    final start = baseDepth.clamp(0, _frames.length);
    final frames = _frames
        .skip(start)
        .map((frame) => frame.toLuaStackFrame())
        .toList();
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
