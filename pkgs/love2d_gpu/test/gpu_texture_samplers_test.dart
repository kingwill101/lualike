import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d_gpu/src/renderer/gpu_texture_samplers.dart';

void main() {
  test('LOVE default linear filter maps to a linear clamp sampler', () {
    final image = _image();

    final sampler = gpuSamplerForLoveImage(image);

    expect(sampler.minFilter, gpu.MinMagFilter.linear);
    expect(sampler.magFilter, gpu.MinMagFilter.linear);
    expect(sampler.mipFilter, gpu.MipFilter.nearest);
    expect(sampler.widthAddressMode, gpu.SamplerAddressMode.clampToEdge);
    expect(sampler.heightAddressMode, gpu.SamplerAddressMode.clampToEdge);
    expect(gpuSamplerForLoveImage(image), same(sampler));
  });

  test('LOVE nearest and wrap modes map independently per axis', () {
    final image = _image(
      filter: const LoveGraphicsDefaultFilter(
        min: LoveGraphicsFilterMode.nearest,
        mag: LoveGraphicsFilterMode.linear,
      ),
      wrap: const LoveGraphicsWrap(
        horizontal: LoveGraphicsWrapMode.repeat,
        vertical: LoveGraphicsWrapMode.mirroredRepeat,
      ),
    );

    final sampler = gpuSamplerForLoveImage(image);

    expect(sampler.minFilter, gpu.MinMagFilter.nearest);
    expect(sampler.magFilter, gpu.MinMagFilter.linear);
    expect(sampler.widthAddressMode, gpu.SamplerAddressMode.repeat);
    expect(sampler.heightAddressMode, gpu.SamplerAddressMode.mirror);
  });

  test('LOVE clampzero uses the closest flutter_gpu address mode', () {
    final sampler = gpuSamplerForLoveImage(
      _image(
        wrap: const LoveGraphicsWrap(
          horizontal: LoveGraphicsWrapMode.clampZero,
          vertical: LoveGraphicsWrapMode.clampZero,
        ),
      ),
    );

    expect(sampler.widthAddressMode, gpu.SamplerAddressMode.clampToEdge);
    expect(sampler.heightAddressMode, gpu.SamplerAddressMode.clampToEdge);
  });
}

LoveImage _image({
  LoveGraphicsDefaultFilter filter = LoveGraphicsDefaultFilter.standard,
  LoveGraphicsWrap wrap = LoveGraphicsWrap.clamp,
}) {
  return LoveImage(
    source: 'sampler-test',
    width: 8,
    height: 8,
    filter: filter,
    wrap: wrap,
  );
}
