import 'package:lualike/lualike.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/utils/file_system_utils.dart';
import 'package:lualike/src/utils/io_abstractions.dart';
import 'package:lualike/src/utils/platform_utils.dart' as platform;
import 'package:path/path.dart' as path_lib;

class OSLibrary {
  static final Map<String, BuiltinFunction> _functions = {
    'clock': _OSClock(),
    'date': _OSDate(),
    'difftime': _OSDiffTime(),
    'execute': _OSExecute(),
    'exit': _OSExit(),
    'getenv': _OSGetEnv(),
    'remove': _OSRemove(),
    'rename': _OSRename(),
    'setlocale': _OSSetLocale(),
    'time': _OSTime(),
    'tmpname': _OSTmpName(),
  };

  // Add a public getter to access the private _functions field
  static Map<String, BuiltinFunction> get functions => _functions;
}

class _OSClock implements BuiltinFunction {
  static final _start = DateTime.now();

  @override
  Object? call(List<Object?> args) {
    // Return CPU time in seconds
    final elapsed = DateTime.now().difference(_start);
    return Value(elapsed.inMicroseconds / 1000000.0);
  }
}

class _OSDate implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    String format = args.isNotEmpty ? (args[0] as Value).raw.toString() : "%c";
    DateTime time;
    bool useUTC = false;

    // Handle UTC prefix
    if (format.startsWith("!")) {
      useUTC = true;
      format = format.substring(1);
    }

    if (args.length > 1) {
      final timestamp = (args[1] as Value).raw as int;
      time = DateTime.fromMillisecondsSinceEpoch(
        timestamp * 1000,
        isUtc: useUTC,
      );
      if (!useUTC) {
        time = time.toLocal();
      }
    } else {
      time = useUTC ? DateTime.now().toUtc() : DateTime.now();
    }

    if (format == "*t") {
      // Return a table
      final table = <dynamic, dynamic>{};
      table["year"] = Value(time.year);
      table["month"] = Value(time.month);
      table["day"] = Value(time.day);
      table["hour"] = Value(time.hour);
      table["min"] = Value(time.minute);
      table["sec"] = Value(time.second);
      table["wday"] = Value((time.weekday % 7) + 1); // 1-7, Sunday is 1
      table["yday"] = Value(_OSDate._getDayOfYear(time));
      table["isdst"] = Value(false); // No DST in Dart

      return Value(table);
    } else {
      // Format the date according to the format string
      return Value(_formatDate(time, format));
    }
  }

  static int _getDayOfYear(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    return date.difference(startOfYear).inDays + 1;
  }

  String _formatDate(DateTime date, String format) {
    // Handle empty string case
    if (format.isEmpty) {
      return "";
    }

    // Check for invalid conversion specifiers
    _validateFormat(format);

    // Simple implementation of strftime-like formatting
    var result = format;

    // Handle %% first (literal % character)
    result = result.replaceAll("%%", "\uE000"); // Temporary placeholder

    // Basic format specifiers
    result = result.replaceAll("%Y", date.year.toString());
    result = result.replaceAll("%m", date.month.toString().padLeft(2, '0'));
    result = result.replaceAll("%d", date.day.toString().padLeft(2, '0'));
    result = result.replaceAll("%H", date.hour.toString().padLeft(2, '0'));
    result = result.replaceAll("%M", date.minute.toString().padLeft(2, '0'));
    result = result.replaceAll("%S", date.second.toString().padLeft(2, '0'));

    // Week day (0=Sunday, 1=Monday, ..., 6=Saturday)
    result = result.replaceAll("%w", ((date.weekday % 7)).toString());

    // Year day (1-366)
    result = result.replaceAll(
      "%j",
      _getDayOfYear(date).toString().padLeft(3, '0'),
    );

    // %c - Preferred date and time representation
    if (result.contains("%c")) {
      final dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
      final monthNames = [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec",
      ];

      final dayName = dayNames[date.weekday % 7];
      final monthName = monthNames[date.month - 1];

      result = result.replaceAll(
        "%c",
        "$dayName $monthName ${date.day.toString().padLeft(2, ' ')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')} ${date.year}",
      );
    }

    // Restore literal % characters
    result = result.replaceAll("\uE000", "%");

    return result;
  }

  void _validateFormat(String format) {
    // Find all % specifiers
    final pattern = RegExp(r'%(.?)');
    final matches = pattern.allMatches(format);

    for (final match in matches) {
      final specifier = match.group(1);
      if (specifier == null || specifier.isEmpty) {
        throw LuaError("invalid conversion specifier");
      }

      // Valid single-character specifiers
      const validSpecifiers = {
        'Y',
        'm',
        'd',
        'H',
        'M',
        'S',
        'w',
        'j',
        'c',
        '%',
      };

      if (specifier.length == 1) {
        if (!validSpecifiers.contains(specifier)) {
          throw LuaError("invalid conversion specifier");
        }
      } else {
        // Multi-character specifiers like %E, %O are not supported
        throw LuaError("invalid conversion specifier");
      }
    }
  }
}

class _OSDiffTime implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError("os.difftime requires two timestamps");
    }

    final t2 = (args[0] as Value).raw as int;
    final t1 = (args[1] as Value).raw as int;

    return Value(t2 - t1);
  }
}

class _OSExecute implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      // Check if shell is available
      return Value(platform.isWindows || platform.isLinux || platform.isMacOS);
    }

    final command = (args[0] as Value).raw.toString();
    try {
      final result = runProcessSync(
        platform.isWindows ? 'cmd' : 'sh',
        platform.isWindows ? ['/c', command] : ['-c', command],
      );

      if (result.exitCode == 0) {
        return [Value(true), Value('exit'), Value(0)];
      } else {
        return [Value(false), Value('exit'), Value(result.exitCode)];
      }
    } catch (e) {
      return [Value(false), Value('error'), Value(e.toString())];
    }
  }
}

class _OSExit implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    final code = args.isNotEmpty ? (args[0] as Value).raw as int : 0;
    exitProcess(code);
    return null;
  }
}

class _OSGetEnv implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("os.getenv requires a variable name");
    }

    final name = (args[0] as Value).raw.toString();
    final value = platform.getEnvironmentVariable(name);

    return Value(value);
  }
}

class _OSRemove implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError.typeError("os.remove requires a filename");
    }

    final filename = path_lib.normalize((args[0] as Value).raw.toString());

    try {
      if (await fileExists(filename)) {
        await deleteFile(filename);
        return Value.multi([Value(true)]);
      } else {
        return Value.multi([Value(null), Value("No such file or directory")]);
      }
    } catch (e) {
      return Value.multi([Value(null), Value(e.toString())]);
    }
  }
}

class _OSRename implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError.typeError("os.rename requires old and new names");
    }

    final oldName = path_lib.normalize((args[0] as Value).raw.toString());
    final newName = path_lib.normalize((args[1] as Value).raw.toString());

    try {
      if (await fileExists(oldName)) {
        await renameFile(oldName, newName);
        return Value.multi([Value(true)]);
      } else {
        return Value.multi([Value(null), Value("No such file or directory")]);
      }
    } catch (e) {
      return Value.multi([Value(null), Value(e.toString())]);
    }
  }
}

class _OSSetLocale implements BuiltinFunction {
  static String? _currentLocale;

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      return Value(_currentLocale ?? 'C');
    }

    final localeArg = args[0] as Value;
    // final category =
    //     args.length > 1 ? (args[1] as Value).raw.toString() : 'all';

    // If locale argument is nil, return current locale
    if (localeArg.raw == null) {
      return Value(_currentLocale ?? 'C');
    }

    final locale = localeArg.raw.toString();

    // We only support the "C" locale since we don't implement
    // locale-specific functionality like collation
    if (locale == '') {
      _currentLocale = 'C'; // Default to C locale
    } else if (locale == 'C' || locale == 'POSIX') {
      _currentLocale = 'C';
    } else {
      // For any other locale, return nil since we don't support it
      return Value(null);
    }
    return Value(_currentLocale);
  }
}

class _OSTime implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      // Return current time
      return Value((DateTime.now().millisecondsSinceEpoch / 1000).floor());
    } else {
      // Convert table to timestamp
      final arg = args[0] as Value;
      if (arg.raw is! Map) {
        throw LuaError.typeError("table expected");
      }

      final table = arg.raw as Map;

      // Extract required fields
      final year = _getTableField(table, "year");
      final month = _getTableField(table, "month");
      final day = _getTableField(table, "day");

      if (year == null || month == null || day == null) {
        throw LuaError("missing date field(s)");
      }

      // Check bounds for year field (matching Lua's behavior)
      if (year < -2147481748 || year > 2147485547) {
        throw LuaError("field 'year' is out-of-bound");
      }

      // Extract optional fields
      final hour = _getTableField(table, "hour") ?? 12;
      final min = _getTableField(table, "min") ?? 0;
      final sec = _getTableField(table, "sec") ?? 0;

      try {
        // Create DateTime which will normalize the fields
        final date = DateTime(year, month, day, hour, min, sec);

        // Update the original table with normalized values
        _updateTableField(table, "year", date.year);
        _updateTableField(table, "month", date.month);
        _updateTableField(table, "day", date.day);
        _updateTableField(table, "hour", date.hour);
        _updateTableField(table, "min", date.minute);
        _updateTableField(table, "sec", date.second);
        _updateTableField(table, "yday", _OSDate._getDayOfYear(date));

        return Value((date.millisecondsSinceEpoch / 1000).floor());
      } catch (e) {
        throw LuaError("field 'year' is out-of-bound");
      }
    }
  }

  int? _getTableField(Map table, String key) {
    final value = table[key];
    if (value == null) return null;
    if (value is Value) {
      final raw = value.raw;
      if (raw is int) return raw;
      if (raw is double) {
        // Check if it's actually an integer value
        if (raw != raw.truncateToDouble()) {
          throw LuaError("not an integer");
        }
        return raw.toInt();
      }
      if (raw is String) {
        throw LuaError("not an integer");
      }
      throw LuaError("not an integer");
    }
    if (value is int) return value;
    if (value is double) {
      // Check if it's actually an integer value
      if (value != value.truncateToDouble()) {
        throw LuaError("not an integer");
      }
      return value.toInt();
    }
    throw LuaError("not an integer");
  }

  void _updateTableField(Map table, String key, int value) {
    // Always update the field in the table (add if not present)
    table[key] = Value(value);
  }
}

class _OSTmpName implements BuiltinFunction {
  static int _counter = 0;

  @override
  Object? call(List<Object?> args) {
    final tmpdir = getSystemTempDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _counter++;
    return Value('$tmpdir/lua_${timestamp}_$_counter.tmp');
  }
}

void defineOSLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  final osTable = <String, dynamic>{};
  OSLibrary.functions.forEach((key, value) {
    osTable[key] = value;
  });
  env.define("os", osTable);
}
