import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/src/runtime/flame/love_registered_fragment_shader_cache.dart';

void main() {
  group('LoveRegisteredFragmentShaderCache', () {
    test(
      'loads queued assets and creates fresh shaders from cached programs',
      () async {
        final completer = Completer<String>();
        var shaderCreations = 0;
        final cache = LoveRegisteredFragmentShaderCache<String, String>(
          loadProgram: (_) => completer.future,
          createShader: (program) => 'shader:${shaderCreations++}:$program',
          scheduleTask: (callback) => callback(),
        );

        cache.queueWarmup('assets/shaders/water.frag');
        await Future<void>.delayed(Duration.zero);

        expect(
          cache.statusForAsset('assets/shaders/water.frag').state,
          LoveRegisteredFragmentShaderLoadState.pending,
        );

        completer.complete('program:water');
        await Future<void>.delayed(Duration.zero);

        expect(
          cache.statusForAsset('assets/shaders/water.frag').state,
          LoveRegisteredFragmentShaderLoadState.ready,
        );
        final firstShader = cache.shaderForAsset(
          'assets/shaders/water.frag',
          explicitLoveShaderRequest: false,
        );
        final secondShader = cache.shaderForAsset(
          'assets/shaders/water.frag',
          explicitLoveShaderRequest: false,
        );

        expect(firstShader, 'shader:0:program:water');
        expect(secondShader, 'shader:1:program:water');
        expect(secondShader, isNot(firstShader));
      },
    );

    test(
      'reports prewarm failures once the asset is requested by LOVE',
      () async {
        final reported = <String>[];
        final cache = LoveRegisteredFragmentShaderCache<String, String>(
          loadProgram: (_) async => throw StateError('compile failed'),
          createShader: (program) => 'shader:$program',
          scheduleTask: (callback) => callback(),
          reportError: (assetKey, error, _) {
            reported.add('$assetKey:$error');
          },
        );

        cache.queueWarmup('assets/shaders/broken.frag');
        await Future<void>.delayed(Duration.zero);

        expect(reported, isEmpty);
        expect(
          cache.statusForAsset('assets/shaders/broken.frag').state,
          LoveRegisteredFragmentShaderLoadState.error,
        );

        cache.markAssetRequested('assets/shaders/broken.frag');

        expect(
          reported,
          contains('assets/shaders/broken.frag:Bad state: compile failed'),
        );

        cache.markAssetRequested('assets/shaders/broken.frag');
        expect(reported.length, 1);
      },
    );

    test(
      'diagnosticForAssets prefers explicit errors over pending work',
      () async {
        final pendingCompleter = Completer<String>();
        final cache = LoveRegisteredFragmentShaderCache<String, String>(
          loadProgram: (assetKey) {
            if (assetKey.endsWith('pending.frag')) {
              return pendingCompleter.future;
            }
            throw StateError('broken shader');
          },
          createShader: (program) => 'shader:$program',
          scheduleTask: (callback) => callback(),
          reportError: (assetKey, error, stackTrace) {},
        );

        cache.markAssetRequested('assets/shaders/broken.frag');
        await Future<void>.delayed(Duration.zero);
        cache.markAssetRequested('assets/shaders/pending.frag');
        await Future<void>.delayed(Duration.zero);

        final diagnostic = cache.diagnosticForAssets(const <String>[
          'assets/shaders/pending.frag',
          'assets/shaders/broken.frag',
        ]);

        expect(diagnostic, isNotNull);
        expect(diagnostic!.assetKey, 'assets/shaders/broken.frag');
        expect(diagnostic.state, LoveRegisteredFragmentShaderLoadState.error);

        pendingCompleter.complete('program:pending');
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      'prewarmShaderAssetsInBundle queues shader-like assets from the manifest',
      () async {
        final loaded = <String>[];
        final cache = LoveRegisteredFragmentShaderCache<String, String>(
          loadProgram: (assetKey) async {
            loaded.add(assetKey);
            return 'program:$assetKey';
          },
          createShader: (program) => 'shader:$program',
          scheduleTask: (callback) => callback(),
        );
        final bundle = _MapAssetBundle(<String, List<int>>{
          'AssetManifest.bin': _encodeAssetManifest(<String>[
            'assets/images/logo.png',
            'assets/shaders/water.frag',
            'assets/shaders/laser.glsl',
            'packages/love2d/test_assets/shaders/runtime_effect_solid_color.frag',
          ]),
        });

        await cache.prewarmShaderAssetsInBundle(bundle);
        await Future<void>.delayed(Duration.zero);

        expect(loaded, <String>[
          'assets/shaders/laser.glsl',
          'assets/shaders/water.frag',
          'packages/love2d/test_assets/shaders/runtime_effect_solid_color.frag',
        ]);
        expect(
          cache.statusForAsset('assets/shaders/water.frag').state,
          LoveRegisteredFragmentShaderLoadState.ready,
        );
        expect(
          cache.statusForAsset('assets/images/logo.png').state,
          LoveRegisteredFragmentShaderLoadState.idle,
        );
      },
    );
  });
}

class _MapAssetBundle extends CachingAssetBundle {
  _MapAssetBundle(this._assets);

  final Map<String, List<int>> _assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) {
      throw StateError('Missing asset: $key');
    }

    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

List<int> _encodeAssetManifest(List<String> assetKeys) {
  final manifest = <String, List<Map<String, Object?>>>{
    for (final assetKey in assetKeys)
      assetKey: <Map<String, Object?>>[
        <String, Object?>{'asset': assetKey},
      ],
  };
  final encoded = const StandardMessageCodec().encodeMessage(manifest);
  if (encoded == null) {
    throw StateError('Failed to encode test asset manifest');
  }
  return encoded.buffer.asUint8List(
    encoded.offsetInBytes,
    encoded.lengthInBytes,
  );
}
