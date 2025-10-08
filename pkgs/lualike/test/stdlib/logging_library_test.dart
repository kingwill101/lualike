import 'package:logging/logging.dart' as pkg_logging;
import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    Logger.initialize(defaultLevel: pkg_logging.Level.INFO);
    Logger.setEnabled(false);
    Logger.setCategoryFilter(null);
    Logger.setLevelFilter(null);
    Logger.setDefaultLevel(pkg_logging.Level.INFO);
  });

  tearDown(() {
    Logger.setEnabled(false);
    Logger.setCategoryFilter(null);
    Logger.setLevelFilter(null);
    Logger.setDefaultLevel(pkg_logging.Level.INFO);
  });

  test('logging.enable and logging.disable toggle verbose logging', () async {
    final bridge = LuaLike();
    await bridge.execute('logging.enable()');
    expect(Logger.enabled, isTrue);
    expect(Logger.logLevelFilter, equals(pkg_logging.Level.FINE));

    await bridge.execute('logging.disable()');
    expect(Logger.enabled, isFalse);
  });

  test('logging.set_level updates filters from Lua', () async {
    final bridge = LuaLike();
    await bridge.execute('logging.set_level("WARNING")');
    expect(Logger.logLevelFilter, equals(pkg_logging.Level.WARNING));
    expect(pkg_logging.Logger.root.level, equals(pkg_logging.Level.WARNING));
  });

  test('logging.set_category and reset_filters update configuration', () async {
    final bridge = LuaLike();
    await bridge.execute('logging.set_category("IO")');
    expect(Logger.logCategoryFilter, equals('IO'));

    await bridge.execute('logging.reset_filters()');
    expect(Logger.logCategoryFilter, isNull);
    expect(Logger.logLevelFilter, isNull);
    expect(pkg_logging.Logger.root.level, equals(pkg_logging.Level.INFO));
  });

  test('logging getters return current state into Lua globals', () async {
    final bridge = LuaLike();
    await bridge.execute('''
      logging.enable("INFO")
      current_level = logging.get_level()
      current_category = logging.get_category()
      is_on = logging.is_enabled()
      logging.disable()
      is_off = logging.is_enabled()
    ''');

    final levelValue = bridge.getGlobal('current_level') as Value;
    final categoryValue = bridge.getGlobal('current_category') as Value;
    final isOnValue = bridge.getGlobal('is_on') as Value;
    final isOffValue = bridge.getGlobal('is_off') as Value;

    expect(levelValue.raw, equals('INFO'));
    expect(categoryValue.raw, isNull);
    expect(isOnValue.raw, isTrue);
    expect(isOffValue.raw, isFalse);
  });
}
