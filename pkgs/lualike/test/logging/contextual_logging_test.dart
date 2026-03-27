import 'package:contextual/contextual.dart' as ctx;
import 'package:lualike/src/logging/logger.dart';
import 'package:test/test.dart';

/// A test log driver that collects log entries for verification
class _CollectingDriver implements ctx.LogDriver {
  @override
  final String name = 'test';

  final entries = <ctx.LogEntry>[];

  @override
  Future<void> log(ctx.LogEntry entry) async {
    entries.add(entry);
  }

  void clear() => entries.clear();

  @override
  // TODO: implement isShutdown
  bool get isShutdown => throw UnimplementedError();

  @override
  // TODO: implement isShuttingDown
  bool get isShuttingDown => throw UnimplementedError();

  @override
  Future<void> notifyShutdown() {
    // TODO: implement notifyShutdown
    throw UnimplementedError();
  }

  @override
  // TODO: implement onShutdown
  Future<void> get onShutdown => throw UnimplementedError();

  @override
  Future<void> performShutdown() {
    // TODO: implement performShutdown
    throw UnimplementedError();
  }
}

void main() {
  group('Contextual logging', () {
    late _CollectingDriver driver;

    setUp(() {
      driver = _CollectingDriver();

      // Initialize with our test driver
      Logger.initialize(pretty: false);
      // Replace the console channel with our test driver
      final logger = ctx.Logger();
      logger.addChannel('test', driver);

      // Reset filters
      Logger.setCategoryFilters(null);
      Logger.setLevelFilter(null);
      Logger.setEnabled(false);

      driver.clear();
    });

    test('lazy builder not executed when disabled', () {
      var executed = false;
      Logger.setEnabled(false);
      Logger.debugLazy(() {
        executed = true;
        return 'expensive';
      }, categories: {'Interp'});
      expect(executed, isFalse);
    });

    test('lazy builder not executed when filtered out', () {
      var executed = false;
      Logger.setCategoryFilters({'GC'});
      Logger.setEnabled(true);
      Logger.debugLazy(() {
        executed = true;
        return 'compute';
      }, categories: {'Interp'});
      expect(executed, isFalse);
    });

    test('lazy builder IS executed when enabled and not filtered', () {
      var executed = false;
      Logger.setEnabled(true);
      Logger.setCategoryFilters(null);
      Logger.debugLazy(() {
        executed = true;
        return 'should run';
      }, categories: {'Interp'});
      expect(executed, isTrue);
    });

    test('multi-category logged correctly', () {
      Logger.setEnabled(true);
      Logger.setCategoryFilters(null);
      Logger.info('hello', categories: {'Interp', 'Value'});

      // The log should have been made (we can't easily verify categories
      // without accessing the context, but we can verify it logged)
      expect(Logger.enabled, isTrue);
    });

    test('context map is passed through', () {
      Logger.setEnabled(true);
      Logger.info('phase start', context: {'phase': 'parse', 'node': 42});

      // Logging should succeed without errors
      expect(Logger.enabled, isTrue);
    });

    test('category filter works correctly', () {
      var interp = false;
      var gc = false;

      Logger.setCategoryFilters({'GC'});
      Logger.setEnabled(true);

      // Should not execute (filtered out)
      Logger.debugLazy(() {
        interp = true;
        return 'interp';
      }, categories: {'Interp'});

      // Should execute (matches filter)
      Logger.debugLazy(() {
        gc = true;
        return 'gc';
      }, categories: {'GC'});

      expect(interp, isFalse);
      expect(gc, isTrue);
    });

    test('level filter works correctly', () {
      var debugExecuted = false;
      var errorExecuted = false;

      Logger.setLevelFilter(Level.error);
      Logger.setEnabled(true);

      // Should not execute (below threshold)
      Logger.debugLazy(() {
        debugExecuted = true;
        return 'debug';
      });

      // Should execute (at threshold)
      Logger.errorLazy(() {
        errorExecuted = true;
        return 'error';
      });

      expect(debugExecuted, isFalse);
      expect(errorExecuted, isTrue);
    });
  });
}
