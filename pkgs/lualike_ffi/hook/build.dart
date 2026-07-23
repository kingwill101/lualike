import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:lualike_ffi/src/c_library.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }
    // The first bridge slice is Linux-only. Unsupported targets keep the Dart
    // API available but report an unavailable capability at runtime.
    if (input.config.code.targetOS.name != 'linux') {
      return;
    }
    await lualikeFfiBridge.run(input: input, output: output);
  });
}
