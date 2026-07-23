import 'package:lualike_ffi/lualike_ffi.dart';

Future<void> main() async {
  const host = NativeFfiHost();
  if (!host.isAvailable) {
    print(host.unavailableReason);
    return;
  }

  final libc = host.open('libc.so.6');
  final abs = host.bind(libc, 'abs', FfiType.i32, const [FfiType.i32]);
  print(abs.call(const [-42]));
  libc.close();
}
