import 'dart:io';
import 'dart:async';

class TestResult {
  final String name;
  final bool passed;
  final bool skipped;
  final String? errorMessage;
  final Duration duration;
  final DateTime timestamp;
  final String? category;

  TestResult({
    required this.name,
    required this.passed,
    this.skipped = false,
    this.errorMessage,
    required this.duration,
    DateTime? timestamp,
    this.category,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'passed': passed,
      'skipped': skipped,
      'errorMessage': errorMessage,
      'durationMs': duration.inMilliseconds,
      'timestamp': timestamp.toIso8601String(),
      'category': category,
    };
  }
}

class Lock {
  Completer<void>? _completer;

  /// Acquire the lock
  Future<void> acquire() async {
    while (_completer != null) {
      await _completer!.future;
    }
    _completer = Completer<void>();
  }

  /// Release the lock
  void release() {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
      _completer = null;
    }
  }

  /// Run a function with the lock held
  Future<T> synchronized<T>(Future<T> Function() fn) async {
    await acquire();
    try {
      return await fn();
    } finally {
      release();
    }
  }
}

class ProgressBar {
  /// Simple mutex lock for synchronizing access to shared resources

  final int total;
  int current = 0;
  final int width;
  final Stopwatch stopwatch = Stopwatch()..start();
  // Lock to prevent concurrent updates to stdout
  final _mutex = Lock();

  ProgressBar({required this.total, this.width = 50});

  Future<void> update(int completed) async {
    current = completed;
    await _render();
  }

  Future<void> increment() async {
    current++;
    await _render();
  }

  Future<void> _render() async {
    // Use mutex to prevent concurrent writes to stdout
    return _mutex.synchronized(() async {
      try {
        final percent = current / total;
        final filled = (width * percent).floor();
        final empty = width - filled;

        final elapsed = stopwatch.elapsed;
        // Avoid division by zero
        final estimatedTotal =
            percent > 0 ? elapsed.inMilliseconds / percent : 0;
        final remaining =
            Duration(milliseconds: estimatedTotal.toInt()) - elapsed;

        final bar = '[${'=' * filled}${' ' * empty}]';
        final percentage = (percent * 100).toStringAsFixed(1).padLeft(5);
        final progress = '$current/$total';
        final eta = 'ETA: ${_formatDuration(remaining)}';

        final output = '\r$bar $percentage% $progress $eta';

        // Use print instead of stdout.write to avoid potential stream issues
        if (current == total) {
          print(output);
        } else {
          stdout.write(output);
        }
      } catch (e) {
        // Silently handle any stdout errors to prevent test failures
        // This is a UI element and shouldn't cause the entire test suite to fail
      }
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
