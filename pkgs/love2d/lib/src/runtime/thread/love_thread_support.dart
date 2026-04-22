part of '../love_runtime.dart';

/// Per-runtime LOVE thread state, including named message channels.
class LoveThreadState {
  /// Creates empty LOVE thread state.
  LoveThreadState();

  /// The thread state attached to each Lua runtime.
  static final Expando<LoveThreadState> _states = Expando<LoveThreadState>(
    'love2d.thread',
  );

  /// Attaches thread state to [runtime].
  ///
  /// Reuses [sharedState] when provided and no state is attached yet.
  static LoveThreadState attach(
    LuaRuntime runtime, {
    LoveThreadState? sharedState,
  }) {
    final existing = _states[runtime];
    if (existing != null) {
      return existing;
    }

    final state = sharedState ?? LoveThreadState();
    _states[runtime] = state;
    return state;
  }

  /// Returns the thread state attached to [runtime].
  static LoveThreadState of(LuaRuntime runtime) {
    return _states[runtime] ?? attach(runtime);
  }

  /// The named LOVE channels visible to this runtime.
  final Map<String, LoveThreadChannel> _namedChannels =
      <String, LoveThreadChannel>{};

  /// Creates a new unnamed channel.
  LoveThreadChannel newChannel() => LoveThreadChannel();

  /// Returns the named channel [name], creating it if needed.
  LoveThreadChannel getChannel(String name) {
    return _namedChannels.putIfAbsent(name, LoveThreadChannel.new);
  }
}

/// A LOVE thread channel that queues values and tracks read acknowledgements.
final class LoveThreadChannel {
  /// The queued channel entries waiting to be read.
  final ListQueue<_LoveThreadChannelEntry> _queue =
      ListQueue<_LoveThreadChannelEntry>();

  /// Waiters blocked on incoming queue entries.
  final ListQueue<Completer<void>> _queueWaiters = ListQueue<Completer<void>>();

  /// The highest message id that has been sent through this channel.
  int _sent = 0;

  /// The highest message id that has been observed as read.
  int _received = 0;

  /// Enqueues [value] and returns its channel message id.
  int push(Object? value) {
    final entry = _LoveThreadChannelEntry(id: ++_sent, value: value);
    _queue.addLast(entry);
    final waiter = _queueWaiters.isEmpty ? null : _queueWaiters.removeFirst();
    waiter?.complete();
    return entry.id;
  }

  /// Enqueues [value] and waits until it has been read or [timeout] elapses.
  Future<bool> supply(Object? value, {double? timeout}) async {
    final entry = _LoveThreadChannelEntry(id: ++_sent, value: value);
    _queue.addLast(entry);
    final waiter = _queueWaiters.isEmpty ? null : _queueWaiters.removeFirst();
    waiter?.complete();

    if (entry.read.isCompleted) {
      return true;
    }

    if (timeout != null) {
      if (timeout <= 0) {
        return entry.read.isCompleted;
      }

      final completed = await Future.any(<Future<bool>>[
        entry.read.future.then((_) => true),
        Future<bool>.delayed(_loveThreadTimeout(timeout), () => false),
      ]);
      return completed;
    }

    await entry.read.future;
    return true;
  }

  /// Removes and returns the next queued value, if any.
  Object? pop() {
    if (_queue.isEmpty) {
      return null;
    }

    final entry = _queue.removeFirst();
    _markRead(entry);
    return entry.value;
  }

  /// Waits for and returns the next queued value.
  ///
  /// Returns `null` when [timeout] expires before a value arrives.
  Future<Object?> demand({double? timeout}) async {
    final immediate = pop();
    if (immediate != null) {
      return immediate;
    }
    if (timeout != null && timeout <= 0) {
      return null;
    }

    final waiter = Completer<void>();
    _queueWaiters.addLast(waiter);
    final woke = timeout == null
        ? await waiter.future.then((_) => true)
        : await Future.any(<Future<bool>>[
            waiter.future.then((_) => true),
            Future<bool>.delayed(_loveThreadTimeout(timeout), () => false),
          ]);

    if (!woke) {
      _queueWaiters.remove(waiter);
      return null;
    }

    return pop();
  }

  /// Returns the next queued value without removing it.
  Object? peek() => _queue.isEmpty ? null : _queue.first.value;

  /// The number of queued unread values.
  int getCount() => _queue.length;

  /// Whether the entry with [id] has already been read.
  bool hasRead(int id) => _received >= id;

  /// Clears the channel and marks all queued entries as read.
  void clear() {
    while (_queue.isNotEmpty) {
      _markRead(_queue.removeFirst());
    }
  }

  /// Marks [entry] as read and updates the received watermark.
  void _markRead(_LoveThreadChannelEntry entry) {
    if (!entry.read.isCompleted) {
      entry.read.complete();
    }
    if (entry.id > _received) {
      _received = entry.id;
    }
  }
}

/// A lightweight async LOVE thread runner backed by a Dart future.
final class LoveLuaThread {
  /// Creates a Lua thread named [name] that executes [runner].
  LoveLuaThread({
    required this.name,
    required Future<void> Function(List<Object?> args, LoveLuaThread thread)
    runner,
    void Function(LoveLuaThread thread, String error)? onError,
  }) : _runner = runner,
       _onError = onError;

  /// The LOVE-visible thread name.
  final String name;

  /// The async task body executed when the thread starts.
  final Future<void> Function(List<Object?> args, LoveLuaThread thread) _runner;

  /// An optional error hook invoked when the task throws.
  final void Function(LoveLuaThread thread, String error)? _onError;

  /// Whether the thread is currently running.
  bool _running = false;

  /// The most recent error message produced by this thread, if any.
  String? _error;

  /// The future for the current running task, if one exists.
  Future<void>? _task;

  /// Whether the thread is currently running.
  bool get isRunning => _running;

  /// The most recent error reported by this thread, if any.
  String? get error => _error;

  /// Starts the thread with [args].
  ///
  /// Returns `false` when the thread is already running.
  bool start(List<Object?> args) {
    if (_running) {
      return false;
    }

    _running = true;
    _error = null;

    final completer = Completer<void>();
    _task = completer.future;

    unawaited(
      Future<void>(() async {
        try {
          await _runner(args, this);
        } catch (error) {
          final message = error.toString();
          _error = message;
          _onError?.call(this, message);
        } finally {
          _running = false;
          if (!completer.isCompleted) {
            completer.complete();
          }
        }
      }),
    );

    return true;
  }

  /// Waits for the current task to complete.
  Future<void> wait() async {
    await _task;
  }
}

/// A queued thread-channel value and the completion used to acknowledge reads.
final class _LoveThreadChannelEntry {
  /// Creates a queued channel entry.
  _LoveThreadChannelEntry({required this.id, required this.value});

  /// The monotonically increasing message id.
  final int id;

  /// The queued channel value.
  final Object? value;

  /// Completes when the value has been read.
  final Completer<void> read = Completer<void>();
}

/// Converts LOVE thread timeout seconds to a non-negative [Duration].
Duration _loveThreadTimeout(double seconds) {
  final microseconds = (seconds * Duration.microsecondsPerSecond).round();
  return Duration(microseconds: math.max(0, microseconds));
}
