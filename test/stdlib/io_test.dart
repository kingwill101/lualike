import 'dart:io';
import 'package:lualike/lualike.dart' show Logger;
import 'package:test/test.dart';
import 'package:lualike/src/io/io_device.dart';
import 'package:lualike/src/io/lua_file.dart';
import 'package:lualike/src/stdlib/lib_io.dart';
import 'package:lualike/src/value.dart';

void main() {
  group('IODevice', () {
    late Directory tempDir;
    late String tempPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
      tempPath = tempDir.path;
      Logger.setEnabled(true);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('FileIODevice basic operations', () async {
      final filePath = '$tempPath/test.txt';
      final device = await FileIODevice.open(filePath, 'w');

      // Write test
      var result = await device.write('Hello, World!\n');
      expect(result.success, true);

      // Seek to beginning
      await device.seek(SeekWhence.set, 0);

      // Read test
      var readResult = await device.read('l');
      expect(readResult.value, 'Hello, World!');

      // Close test
      await device.close();
      expect(device.isClosed, true);
    });

    test('StdinDevice operations', () async {
      final device = StdinDevice();

      // Cannot write to stdin
      var result = await device.write('test');
      expect(result.success, false);

      // Close doesn't affect actual stdin
      await device.close();
      expect(device.isClosed, true);
    });

    test('StdoutDevice operations', () async {
      final device = StdoutDevice(stdout, allowFlush: false);

      // Cannot read from stdout
      var readResult = await device.read();
      expect(readResult.error, isNotNull);

      // Write works
      var writeResult = await device.write('test');
      expect(writeResult.success, true);
    });
  });

  group('LuaFile', () {
    late Directory tempDir;
    late String tempPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
      tempPath = tempDir.path;
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('Basic file operations', () async {
      final filePath = '$tempPath/test.txt';
      final device = await FileIODevice.open(filePath, 'w');
      final file = LuaFile(device);

      // Write test
      var result = await file.write('Hello, World!\n');
      expect(result[0], true);

      // Seek to beginning
      result = await file.seek('set', 0);
      expect(result[0], 0);

      // Read test
      result = await file.read('l');
      expect(result[0], 'Hello, World!');

      // Close test
      result = await file.close();
      expect(result[0], true);
      expect(file.isClosed, true);
    });

    test('Lines iterator', () async {
      final filePath = '$tempPath/test.txt';
      final device = await FileIODevice.open(filePath, 'w');
      final file = LuaFile(device);

      // Write some lines
      await file.write('Line 1\nLine 2\nLine 3\n');
      await file.seek('set', 0);

      // Get lines iterator
      final iterator = await file.lines();
      expect(iterator, isA<Value>());

      // Read lines
      final lines = <String>[];
      final func = iterator.raw as Function;
      while (true) {
        final result = await func([]);
        if (result.raw == null) break;
        lines.add(result.raw as String);
      }

      expect(lines, ['Line 1', 'Line 2', 'Line 3']);
    });
  });

  group('IOLib', () {
    late Directory tempDir;
    late String tempPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
      tempPath = tempDir.path;
      // Reset default streams
      IOLib.defaultInput; // Force creation of new stdin
      IOLib.defaultOutput; // Force creation of new stdout
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('Default streams', () {
      expect(IOLib.defaultInput, isNotNull);
      expect(IOLib.defaultOutput, isNotNull);
    });

    test('File operations', () async {
      final filePath = '$tempPath/test.txt';

      // Open file
      final openFunc = IOLib.functions['open'] as IOOpen;
      final file = await openFunc.call([Value(filePath), Value('w')]);
      expect(file, isA<Value>());
      expect((file as Value).raw, isA<LuaFile>());

      // Set file as default output
      final outputFunc = IOLib.functions['output'] as IOOutput;
      await outputFunc.call([file]);

      // Write to file
      final writeFunc = IOLib.functions['write'] as IOWrite;
      var result = await writeFunc.call([Value('Hello, World!\n')]);
      expect((result as Value).raw[0], true);

      // Close file
      final closeFunc = IOLib.functions['close'] as IOClose;
      result = await closeFunc.call([file]);
      expect((result as Value).raw[0], true);

      // Read file
      final inputFunc = IOLib.functions['input'] as IOInput;
      final readFile = await inputFunc.call([Value(filePath)]);
      expect(readFile, isA<Value>());

      final readFunc = IOLib.functions['read'] as IORead;
      result = await readFunc.call([Value('l')]);
      expect((result as Value).raw[0], 'Hello, World!');
    });

    test('Temporary file', () async {
      // Create temp file
      final tmpFunc = IOLib.functions['tmpfile'] as IOTmpfile;
      final file = await tmpFunc.call([]);
      expect(file, isA<Value>());
      expect((file as Value).raw, isA<LuaFile>());

      // Set temp file as default output
      final outputFunc = IOLib.functions['output'] as IOOutput;
      await outputFunc.call([file]);

      // Write to temp file (now the default output)
      final writeFunc = IOLib.functions['write'] as IOWrite;
      var result = await writeFunc.call([Value('Hello, World!\n')]);
      expect((result as Value).raw[0], true);

      // Close temp file
      final closeFunc = IOLib.functions['close'] as IOClose;
      result = await closeFunc.call([file]);
      expect((result as Value).raw[0], true);

      // Reset default output to stdout
      await outputFunc.call([]);
    });

    test('File type checking', () async {
      final typeFunc = IOLib.functions['type'] as IOType;

      // Non-file value
      var result = await typeFunc.call([Value(42)]);
      expect((result as Value).raw, null);

      // Open file
      final filePath = '$tempPath/test.txt';
      final openFunc = IOLib.functions['open'] as IOOpen;
      final file = await openFunc.call([Value(filePath), Value('w')]);

      // Open file type
      result = await typeFunc.call([file as Value]);
      expect((result as Value).raw, 'file');

      // Close file
      final closeFunc = IOLib.functions['close'] as IOClose;
      await closeFunc.call([file]);

      // Closed file type
      result = await typeFunc.call([file]);
      expect((result as Value).raw, 'closed file');
    });
  });
}
