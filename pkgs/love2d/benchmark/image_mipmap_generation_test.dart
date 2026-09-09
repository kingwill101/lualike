import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  test('compares area and centered mip generation on game-sized images', () {
    final sources = <LoveImageData>[
      _syntheticArt(1214, 1295, seed: 17),
      _syntheticArt(1254, 1254, seed: 41),
    ];

    for (final centered in <bool>[false, true]) {
      for (final source in sources) {
        source.generateMipmaps(centeredLinear: centered);
      }
    }

    final areaSamples = <int>[];
    final centeredSamples = <int>[];
    var checksum = 0;
    for (var pair = 0; pair < ninePairs; pair++) {
      final order = pair.isEven ? <bool>[false, true] : <bool>[true, false];
      for (final centered in order) {
        final stopwatch = Stopwatch()..start();
        for (final source in sources) {
          final levels = source.generateMipmaps(centeredLinear: centered);
          final last = levels.last.getPixel(0, 0);
          checksum =
              (checksum + (last.r * 255).round() + levels.length) & 0x7fffffff;
        }
        stopwatch.stop();
        (centered ? centeredSamples : areaSamples).add(
          stopwatch.elapsedMicroseconds,
        );
      }
    }

    final result = <String, Object>{
      'pairs': ninePairs,
      'sourcePixels': sources.fold<int>(
        0,
        (total, source) => total + (source.width * source.height),
      ),
      'area': _summary(areaSamples),
      'centered': _summary(centeredSamples),
      'checksum': checksum,
    };
    // ignore: avoid_print
    print('MIPMAP_BENCHMARK ${jsonEncode(result)}');
  });
}

const int ninePairs = 9;

LoveImageData _syntheticArt(int width, int height, {required int seed}) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = ((y * width) + x) * 4;
      final value = ((x * 13) + (y * 29) + seed) & 0xff;
      bytes[offset] = value;
      bytes[offset + 1] = (value * 3) & 0xff;
      bytes[offset + 2] = (value * 7) & 0xff;
      bytes[offset + 3] = ((x ^ y ^ seed) & 0x3f) == 0 ? 0 : 255;
    }
  }
  return LoveImageData.fromRgbaBytes(
    width: width,
    height: height,
    bytes: bytes,
  );
}

Map<String, int> _summary(List<int> samples) {
  samples.sort();
  return <String, int>{
    'medianMicros': samples[samples.length ~/ 2],
    'p95Micros':
        samples[((samples.length * 0.95).ceil() - 1).clamp(
          0,
          samples.length - 1,
        )],
    'minMicros': samples.first,
    'maxMicros': samples.last,
  };
}
