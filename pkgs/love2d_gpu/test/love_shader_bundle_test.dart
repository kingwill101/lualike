import 'package:flutter_test/flutter_test.dart';
import 'package:love2d_gpu/src/shader/love_shader_bundle.dart';

void main() {
  test('generated shader bundle precedes the checked-in fallback', () {
    final candidates = loveShaderBundleAssetCandidates(
      'packages/love2d_gpu/assets/love2d_gpu.shaderbundle',
    );

    expect(
      candidates.first,
      'packages/love2d_gpu/build/shaderbundles/love2d_gpu.shaderbundle',
    );
    expect(
      candidates.indexOf(
        'packages/love2d_gpu/build/shaderbundles/love2d_gpu.shaderbundle',
      ),
      lessThan(
        candidates.indexOf(
          'packages/love2d_gpu/assets/love2d_gpu.shaderbundle',
        ),
      ),
    );
    expect(candidates.toSet(), hasLength(candidates.length));
  });
}
