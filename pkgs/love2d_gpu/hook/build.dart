import 'package:flutter_gpu_shaders/build.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildShaderBundleJson(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'love2d_gpu.shaderbundle.json',
      glesLanguageVersion: 300,
      assetMode: ShaderBundleAssetMode.legacyOnly,
    );
  });
}
