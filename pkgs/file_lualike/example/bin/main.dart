import 'package:file/memory.dart';
import 'package:file_lualike/file_lualike.dart';
import 'package:lualike/lualike.dart';

Future<void> main() async {
  final fs = MemoryFileSystem();
  await fs.file('/hello.txt').writeAsString('hello from Dart');
  await useFileSystem(fs);

  final lua = LuaLike();
  final result = await lua.execute('''
    local f = io.open("/hello.txt", "r")
    local contents = f:read("*a")
    f:close()
    return contents
  ''');

  print((result as Value).unwrap());
}
