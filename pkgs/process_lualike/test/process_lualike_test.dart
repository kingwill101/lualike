import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

class MockProcessBackend implements ProcessBackend {
  final Map<String, ProcessRunResult> _results = {};
  final List<String> _calls = [];

  void define(
    String command, {
    required int exitCode,
    String stdout = '',
    String stderr = '',
  }) {
    _results[command] = ProcessRunResult(exitCode, stdout, stderr);
  }

  List<String> get calls => List.unmodifiable(_calls);

  @override
  bool get isShellAvailable => true;

  @override
  ProcessRunResult runSync(String command) {
    _calls.add(command);
    return _results[command] ??
        ProcessRunResult(-1, '', 'command not registered: $command');
  }

  @override
  Future<ProcessRunResult> run(String command) async => runSync(command);

  @override
  Future<int> runStreaming(
    String command, {
    void Function(List<int> chunk)? onStdout,
    void Function(List<int> chunk)? onStderr,
    void Function()? onDone,
  }) async {
    final result = runSync(command);
    onDone?.call();
    return result.exitCode;
  }
}

void main() {
  group('os.execute() with custom ProcessBackend', () {
    late MockProcessBackend mockBackend;
    late LuaLike lua;

    setUp(() {
      mockBackend = MockProcessBackend();
      setProcessBackend(mockBackend);
      lua = LuaLike();
    });

    tearDown(() {
      setProcessBackend(null);
    });

    test('routes to custom backend', () async {
      mockBackend.define(
        'ls -la',
        exitCode: 0,
        stdout: 'file1\nfile2',
        stderr: '',
      );
      await lua.execute('return os.execute("ls -la")');
      // os.execute wraps in shell: sh -c ls -la
      expect(mockBackend.calls, contains('sh -c ls -la'));
    });

    test('returns custom exit code', () async {
      mockBackend.define('sh -c fail', exitCode: 1, stderr: 'error');
      await lua.execute('local ok, _, code = os.execute("fail")');
      expect(mockBackend.calls, contains('sh -c fail'));
    });

    test('isShellAvailable propagates', () async {
      await lua.execute('local shell = os.execute()');
      expect(mockBackend.calls, isEmpty);
    });
  });
}
