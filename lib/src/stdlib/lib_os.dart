import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/lualike.dart';

import 'dart:io' as io;

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

    if (args.length > 1) {
      final timestamp = (args[1] as Value).raw as int;
      time = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    } else {
      time = DateTime.now();
    }

    if (format == "*t") {
      // Return a table
      final table = <dynamic, dynamic>{};
      table[Value("year")] = Value(time.year);
      table[Value("month")] = Value(time.month);
      table[Value("day")] = Value(time.day);
      table[Value("hour")] = Value(time.hour);
      table[Value("min")] = Value(time.minute);
      table[Value("sec")] = Value(time.second);
      table[Value("wday")] = Value((time.weekday % 7) + 1); // 1-7, Sunday is 1
      table[Value("yday")] = Value(_getDayOfYear(time));
      table[Value("isdst")] = Value(false); // No DST in Dart

      return Value(table);
    } else {
      // Format the date according to the format string
      return Value(_formatDate(time, format));
    }
  }

  int _getDayOfYear(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    return date.difference(startOfYear).inDays + 1;
  }

  String _formatDate(DateTime date, String format) {
    // Simple implementation of strftime-like formatting
    format = format.replaceAll("%Y", date.year.toString());
    format = format.replaceAll("%m", date.month.toString().padLeft(2, '0'));
    format = format.replaceAll("%d", date.day.toString().padLeft(2, '0'));
    format = format.replaceAll("%H", date.hour.toString().padLeft(2, '0'));
    format = format.replaceAll("%M", date.minute.toString().padLeft(2, '0'));
    format = format.replaceAll("%S", date.second.toString().padLeft(2, '0'));

    // %c - Preferred date and time representation
    if (format.contains("%c")) {
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

      format = format.replaceAll(
        "%c",
        "$dayName $monthName ${date.day} ${date.hour}:${date.minute}:${date.second} ${date.year}",
      );
    }

    return format;
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
      return Value(
        io.Platform.isWindows || io.Platform.isLinux || io.Platform.isMacOS,
      );
    }

    final command = (args[0] as Value).raw.toString();
    try {
      final result = io.Process.runSync(
        io.Platform.isWindows ? 'cmd' : 'sh',
        io.Platform.isWindows ? ['/c', command] : ['-c', command],
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
    io.exit(code);
  }
}

class _OSGetEnv implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("os.getenv requires a variable name");
    }

    final name = (args[0] as Value).raw.toString();
    final value = io.Platform.environment[name];

    return Value(value);
  }
}

class _OSRemove implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError("os.remove requires a filename");
    }

    final filename = (args[0] as Value).raw.toString();

    try {
      final file = io.File(filename);
      if (file.existsSync()) {
        file.deleteSync();
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
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError("os.rename requires old and new names");
    }

    final oldName = (args[0] as Value).raw.toString();
    final newName = (args[1] as Value).raw.toString();

    try {
      final file = io.File(oldName);
      if (file.existsSync()) {
        file.renameSync(newName);
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
      // TODO: Implement time with table argument
      return Value((DateTime.now().millisecondsSinceEpoch / 1000).floor());
    }
  }
}

class _OSTmpName implements BuiltinFunction {
  static int _counter = 0;

  @override
  Object? call(List<Object?> args) {
    final tmpdir = io.Directory.systemTemp;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _counter++;
    return Value('${tmpdir.path}/lua_${timestamp}_$_counter.tmp');
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
