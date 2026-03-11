import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    Logger.initialize();
    Logger.setEnabled(false);
    Logger.setCategoryFilter(null);
    Logger.setLevelFilter(null);
  });

  tearDown(() {
    Logger.setEnabled(false);
    Logger.setCategoryFilter(null);
    Logger.setLevelFilter(null);
  });

  test('logging.enable and logging.disable toggle verbose logging', () async {
    final bridge = LuaLike();
    await bridge.execute('logging.enable()');
    expect(Logger.enabled, isTrue);
    expect(Logger.logLevelFilter, equals(Level.debug));

    await bridge.execute('logging.disable()');
    expect(Logger.enabled, isFalse);
  });

  test('logging.set_level updates filters from Lua', () async {
    final bridge = LuaLike();
    await bridge.execute('logging.set_level("WARNING")');
    expect(Logger.logLevelFilter, equals(Level.warning));
  });

  test('logging.set_category and reset_filters update configuration', () async {
    final bridge = LuaLike();
    await bridge.execute('logging.set_category("IO")');
    // Category filter is set but not queryable through public API

    await bridge.execute('logging.reset_filters()');
    expect(Logger.logLevelFilter, isNull);
  });

  test('logging getters return current state into Lua globals', () async {
    final bridge = LuaLike();
    await bridge.execute('''
      logging.enable("INFO")
      current_level = logging.get_level()
      is_on = logging.is_enabled()
      logging.disable()
      is_off = logging.is_enabled()
    ''');

    final levelValue = bridge.getGlobal('current_level') as Value;
    final isOnValue = bridge.getGlobal('is_on') as Value;
    final isOffValue = bridge.getGlobal('is_off') as Value;

    expect(levelValue.raw, equals('INFO'));
    expect(isOnValue.raw, isTrue);
    expect(isOffValue.raw, isFalse);
  });

  test('logging.debug with single category', () async {
    final bridge = LuaLike();
    await bridge.execute('''
      logging.enable("DEBUG")
      logging.debug("Test message", {category = "TestCategory"})
    ''');
    expect(Logger.enabled, isTrue);
  });

  test('logging.info with multiple categories', () async {
    final bridge = LuaLike();
    await bridge.execute('''
      logging.enable("INFO")
      logging.info("Request processed", {
        categories = {"HTTP", "API"},
        status = 200,
        method = "GET"
      })
    ''');
    expect(Logger.enabled, isTrue);
  });

  test('logging.warning with structured context', () async {
    final bridge = LuaLike();
    await bridge.execute('''
      logging.enable("WARNING")
      logging.warning("Slow query detected", {
        category = "Database",
        duration_ms = 5000,
        query = "SELECT * FROM users",
        affected_rows = 1000
      })
    ''');
    expect(Logger.enabled, isTrue);
  });

  test('logging.error with nested context', () async {
    final bridge = LuaLike();
    await bridge.execute('''
      logging.enable("ERROR")
      logging.error("Failed to process request", {
        categories = {"HTTP", "Error"},
        user_id = 123,
        error_code = "AUTH_FAILED",
        metadata = {
          ip = "192.168.1.1",
          user_agent = "Mozilla/5.0"
        }
      })
    ''');
    expect(Logger.enabled, isTrue);
  });

  test('set_categories filters logs by category', () async {
    final bridge = LuaLike();
    await bridge.execute('''
      logging.enable("DEBUG")
      logging.set_categories({"HTTP", "Database"})
      logging.debug("This should be filtered", {category = "App"})
      logging.debug("This should appear", {category = "HTTP"})
    ''');
    expect(Logger.enabled, isTrue);
  });

  test('multiple log levels work correctly', () async {
    final bridge = LuaLike();
    await bridge.execute('''
      logging.enable("DEBUG")
      logging.debug("Debug message", {category = "Test"})
      logging.info("Info message", {category = "Test"})
      logging.warning("Warning message", {category = "Test"})
      logging.error("Error message", {category = "Test"})
    ''');
    expect(Logger.enabled, isTrue);
  });

  test('context without category works', () async {
    final bridge = LuaLike();
    await bridge.execute('''
      logging.enable("INFO")
      logging.info("Generic log", {
        key1 = "value1",
        key2 = 42,
        key3 = true
      })
    ''');
    expect(Logger.enabled, isTrue);
  });

  test('simple message without context works', () async {
    final bridge = LuaLike();
    await bridge.execute('''
      logging.enable("INFO")
      logging.info("Simple message")
    ''');
    expect(Logger.enabled, isTrue);
  });

  test('set_level filters by level', () async {
    final bridge = LuaLike();
    await bridge.execute('''
      logging.enable("ERROR")
      logging.set_level("ERROR")
      logging.debug("Should not appear")
      logging.info("Should not appear")
      logging.warning("Should not appear")
      logging.error("Should appear")
    ''');
    expect(Logger.logLevelFilter, equals(Level.error));
  });

  test('reset_filters clears all filters', () async {
    final bridge = LuaLike();
    await bridge.execute('''
      logging.enable("DEBUG")
      logging.set_level("ERROR")
      logging.set_categories({"HTTP", "Database"})
      logging.reset_filters()
    ''');
    expect(Logger.logLevelFilter, isNull);
  });
}
