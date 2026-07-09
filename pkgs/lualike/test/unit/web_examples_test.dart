import '../../web/examples.dart';

import 'package:lualike_test/test.dart';
import 'package:lualike/src/io/memory_io_device.dart';
import 'package:lualike/src/io/virtual_io_device.dart';
import 'package:lualike/src/stdlib/lib_io.dart';

void main() {
  group('Web examples', () {
    setUp(() async {
      await IOLib.reset();
      InMemoryIODevice.clearMemoryStorage();

      final provider = FileSystemProvider(
        providerName: 'WebInMemoryFileSystem',
      );
      provider.setIODeviceFactory(
        createInMemoryIODevice,
        providerName: 'WebInMemoryFileSystem',
      );
      IOLib.fileSystemProvider = provider;
      IOLib.defaultInput = createLuaFile(VirtualIODevice());
    });

    tearDown(() async {
      await IOLib.reset();
      InMemoryIODevice.clearMemoryStorage();
      IOLib.fileSystemProvider = FileSystemProvider();
    });

    for (final key in LuaExamples.keys) {
      test('$key executes in the web harness', () async {
        final lua = LuaLike();
        final stdoutDevice = VirtualIODevice();
        IOLib.defaultOutput = createLuaFile(stdoutDevice);

        try {
          await lua.execute(LuaExamples.getExample(key)!);
        } catch (error) {
          fail(
            'Bundled web example "$key" failed.\n'
            'Captured stdout:\n${stdoutDevice.content}\n'
            'Error: $error',
          );
        }
      });
    }
  });
}
