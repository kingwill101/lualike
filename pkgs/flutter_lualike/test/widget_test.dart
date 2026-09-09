import 'package:flutter/services.dart';
import 'package:flutter_lualike/flutter_lualike.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'AssetBundleIODevice reads bundled bytes and remains read-only',
    () async {
      final bundle = _MemoryAssetBundle(<String, List<int>>{
        'scripts/main.lua': 'return 42'.codeUnits,
      });

      final device = await AssetBundleIODevice.open(
        bundle,
        'scripts/main.lua',
        'r',
      );

      final read = await device.read('a');
      expect(read.isSuccess, isTrue);
      expect(read.value.toString(), 'return 42');
      expect(await device.isEOF(), isTrue);

      final write = await device.write('return 0');
      expect(write.success, isFalse);
      expect(write.error, 'Cannot write to read-only asset bundle');
    },
  );
}

final class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.assets);

  final Map<String, List<int>> assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = assets[key];
    if (bytes == null) {
      throw StateError('Missing test asset: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}
