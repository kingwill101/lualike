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

  test('LOVE linear mipmap filter maps to linear mip sampling', () {
    final sampler = gpuSamplerForLoveImage(
      _image(mipmapCount: 2, mipmapFilter: LoveGraphicsFilterMode.linear),
    );

    expect(sampler.mipFilter, gpu.MipFilter.linear);
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

  test('textures without mipmaps do not receive an LOD bias', () {
    final image = _image(mipmapSharpness: 0.75);

    expect(gpuMipmapLodBiasForLoveImage(image, compensation: -0.5), 0.0);
  });

  test('mipmap LOD bias combines LOVE sharpness and GPU compensation', () {
    final image = _image(mipmapCount: 4, mipmapSharpness: 0.25);

    expect(gpuMipmapLodBiasForLoveImage(image, compensation: -0.5), -0.75);
  });

  test('default mipmap LOD bias applies only LOVE sharpness', () {
    final image = _image(mipmapCount: 4, mipmapSharpness: 0.25);

    expect(loveGpuMipmapLodCompensation, 0.0);
    expect(gpuMipmapLodBiasForLoveImage(image, effectiveScale: 0.145), -0.25);
  });

  test('adaptive LOD compensation preserves large near-base images', () {
    final image = _image(mipmapCount: 4, mipmapSharpness: 0.25);

    expect(
      gpuMipmapLodBiasForLoveImage(
        image,
        compensation: -0.5,
        effectiveScale: 0.64,
        adaptiveCompensation: true,
      ),
      -0.25,
    );
  });

  test('adaptive LOD compensation ramps into strong minification', () {
    final image = _image(mipmapCount: 4, mipmapSharpness: 0.25);

    expect(
      gpuMipmapLodBiasForLoveImage(
        image,
        compensation: -0.5,
        effectiveScale: 0.375,
        adaptiveCompensation: true,
      ),
      -0.5,
    );
    expect(
      gpuMipmapLodBiasForLoveImage(
        image,
        compensation: -0.5,
        effectiveScale: 0.145,
        adaptiveCompensation: true,
      ),
      -0.75,
    );
  });

  test('adaptive LOD compensation can be disabled for reverse A/B', () {
    final image = _image(mipmapCount: 4, mipmapSharpness: 0.25);

    expect(
      gpuMipmapLodBiasForLoveImage(
        image,
        compensation: -0.5,
        effectiveScale: 0.64,
        adaptiveCompensation: false,
      ),
      -0.75,
    );
  });
}

LoveImage _image({
  LoveGraphicsDefaultFilter filter = LoveGraphicsDefaultFilter.standard,
  LoveGraphicsWrap wrap = LoveGraphicsWrap.clamp,
  int mipmapCount = 1,
  LoveGraphicsFilterMode? mipmapFilter,
  double mipmapSharpness = 0.0,
}) {
  return LoveImage(
    source: 'sampler-test',
    width: 8,
    height: 8,
    filter: filter,
    wrap: wrap,
    mipmapCount: mipmapCount,
    mipmapFilter: mipmapFilter,
    mipmapSharpness: mipmapSharpness,
  );
}
