import 'dart:io';

import 'package:lualike_ffi/lualike_ffi.dart';
import 'package:test/test.dart';

void main() {
  test(
    'loads a shared library and calls runtime-declared symbols',
    () {
      const host = NativeFfiHost();
      final library = host.open('libc.so.6');
      addTearDown(library.close);

      final strlen = host.bind(library, 'strlen', FfiType.u64, const [
        FfiType.string,
      ]);
      final abs = host.bind(library, 'abs', FfiType.i32, const [FfiType.i32]);
      final getpid = host.bind(library, 'getpid', FfiType.i32, const []);

      expect(strlen.call(const ['lualike']), 7);
      expect(abs.call(const [-42]), 42);
      expect(getpid.call(const []), pid);
    },
    skip: Platform.isLinux ? false : 'Linux bridge prototype',
  );

  test(
    'rejects calls after the owning library closes',
    () {
      const host = NativeFfiHost();
      final library = host.open('libc.so.6');
      final abs = host.bind(library, 'abs', FfiType.i32, const [FfiType.i32]);
      library.close();

      expect(() => abs.call(const [-1]), throwsA(isA<FfiException>()));
    },
    skip: Platform.isLinux ? false : 'Linux bridge prototype',
  );
}
