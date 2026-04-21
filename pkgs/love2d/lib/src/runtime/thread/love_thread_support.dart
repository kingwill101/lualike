part of '../love_runtime.dart';

class LoveThreadState {
  LoveThreadState();

  static final Expando<LoveThreadState> _states = Expando<LoveThreadState>(
    'love2d.thread',
  );

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

  static LoveThreadState of(LuaRuntime runtime) {
    return _states[runtime] ?? attach(runtime);
  }

  final Map<String, LoveThreadChannel> _namedChannels =
      <String, LoveThreadChannel>{};

  LoveThreadChannel newChannel() => LoveThreadChannel();

  LoveThreadChannel getChannel(String name) {
    return _namedChannels.putIfAbsent(name, LoveThreadChannel.new);
  }
}

final class LoveThreadChannel {
  final ListQueue<_LoveThreadChannelEntry> _queue =
      ListQueue<_LoveThreadChannelEntry>();
  final ListQueue<Completer<void>> _queueWaiters = ListQueue<Completer<void>>();
  int _sent = 0;
  int _received = 0;

  int push(Object? value) {
    final entry = _LoveThreadChannelEntry(id: ++_sent, value: value);
    _queue.addLast(entry);
    final waiter = _queueWaiters.isEmpty ? null : _queueWaiters.removeFirst();
    waiter?.complete();
    return entry.id;
  }

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

  Object? pop() {
    if (_queue.isEmpty) {
      return null;
    }

    final entry = _queue.removeFirst();
    _markRead(entry);
    return entry.value;
  }

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

  Object? peek() => _queue.isEmpty ? null : _queue.first.value;

  int getCount() => _queue.length;

  bool hasRead(int id) => _received >= id;

  void clear() {
    while (_queue.isNotEmpty) {
      _markRead(_queue.removeFirst());
    }
  }

  void _markRead(_LoveThreadChannelEntry entry) {
    if (!entry.read.isCompleted) {
      entry.read.complete();
    }
    if (entry.id > _received) {
      _received = entry.id;
    }
  }
}

final class LoveLuaThread {
  LoveLuaThread({
    required this.name,
    required Future<void> Function(List<Object?> args, LoveLuaThread thread)
    runner,
    void Function(LoveLuaThread thread, String error)? onError,
  }) : _runner = runner,
       _onError = onError;

  final String name;
  final Future<void> Function(List<Object?> args, LoveLuaThread thread) _runner;
  final void Function(LoveLuaThread thread, String error)? _onError;

  bool _running = false;
  String? _error;
  Future<void>? _task;

  bool get isRunning => _running;

  String? get error => _error;

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

  Future<void> wait() async {
    await _task;
  }
}

final class _LoveThreadChannelEntry {
  _LoveThreadChannelEntry({required this.id, required this.value});

  final int id;
  final Object? value;
  final Completer<void> read = Completer<void>();
}

Duration _loveThreadTimeout(double seconds) {
  final microseconds = (seconds * Duration.microsecondsPerSecond).round();
  return Duration(microseconds: math.max(0, microseconds));
}
