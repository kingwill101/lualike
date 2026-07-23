import 'dart:io';

import 'package:ffigen/ffigen.dart';

void main() {
  final packageRoot = Platform.script.resolve('../');
  FfiGenerator(
    output: Output(
      dartFile: packageRoot.resolve('lib/src/lualike_ffi_bindings.g.dart'),
      preamble: '''
// Copyright (c) 2026, the lualike authors.
// Use of this source code is governed by the MIT license in the LICENSE file.
''',
      style: const NativeExternalBindings(
        assetId: 'package:lualike_ffi/src/lualike_ffi_bindings.g.dart',
      ),
    ),
    headers: Headers(
      entryPoints: [packageRoot.resolve('native/lualike_ffi.h')],
    ),
    functions: Functions.includeSet({
      'lualike_ffi_open',
      'lualike_ffi_close',
      'lualike_ffi_symbol',
      'lualike_ffi_call',
    }),
    unions: Unions.includeSet({'lualike_ffi_value'}),
  ).generate();
}
