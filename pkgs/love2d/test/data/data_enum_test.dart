import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.data enum tables', () {
    test('are exposed globally and in the module namespace', () {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      final globals = runtime.runtime.globals;
      final love = globals.get('love');
      expect(love, isA<Value>());
      final loveTable = (love! as Value).raw as Map;

      final data = loveTable['data'];
      expect(data, isA<Value>());
      final dataTable = (data! as Value).raw as Map;

      final expectedEnums = <String, List<String>>{
        'CompressedDataFormat': <String>['lz4', 'zlib', 'gzip', 'deflate'],
        'ContainerType': <String>['data', 'string'],
        'EncodeFormat': <String>['base64', 'hex'],
        'HashFunction': <String>[
          'md5',
          'sha1',
          'sha224',
          'sha256',
          'sha384',
          'sha512',
        ],
      };

      for (final entry in expectedEnums.entries) {
        final globalEnum = globals.get(entry.key);
        expect(globalEnum, isA<Value>(), reason: 'Missing global ${entry.key}');
        final globalTable = (globalEnum! as Value).raw as Map;

        final moduleEnum = dataTable[entry.key];
        expect(
          moduleEnum,
          isA<Value>(),
          reason: 'Missing love.data.${entry.key}',
        );
        final moduleTable = (moduleEnum! as Value).raw as Map;

        expect(identical(globalTable, moduleTable), isTrue);
        expect(globalTable.length, entry.value.length);

        for (final constant in entry.value) {
          expect(globalTable[constant], constant);
          expect(moduleTable[constant], constant);
        }
      }
    });

    test('can be used as LOVE string constants in Lua code', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
testbed = {}

testbed.global_container = ContainerType.string
testbed.module_container = love.data.ContainerType.data
testbed.global_encode = EncodeFormat.hex
testbed.module_encode = love.data.EncodeFormat.base64
testbed.global_compressed = CompressedDataFormat.zlib
testbed.module_compressed = love.data.CompressedDataFormat.gzip
testbed.global_hash = HashFunction.sha256
testbed.module_hash = love.data.HashFunction.md5

testbed.hex = love.data.encode(ContainerType.string, EncodeFormat.hex, "Hi")
local digest = love.data.hash(HashFunction.sha256, "abc")
testbed.digest_hex = love.data.encode("string", "hex", digest)

local compressed = love.data.compress(
  ContainerType.data,
  love.data.CompressedDataFormat.zlib,
  "payload"
)
testbed.compressed_type = compressed:type()
testbed.compressed_format = compressed:getFormat()
testbed.roundtrip = love.data.decompress(ContainerType.string, compressed)
''');

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['global_container'], 'string');
      expect(snapshot['module_container'], 'data');
      expect(snapshot['global_encode'], 'hex');
      expect(snapshot['module_encode'], 'base64');
      expect(snapshot['global_compressed'], 'zlib');
      expect(snapshot['module_compressed'], 'gzip');
      expect(snapshot['global_hash'], 'sha256');
      expect(snapshot['module_hash'], 'md5');
      expect(snapshot['hex'], '4869');
      expect(
        snapshot['digest_hex'],
        'ba7816bf8f01cfea414140de5dae2223'
        'b00361a396177a9cb410ff61f20015ad',
      );
      expect(snapshot['compressed_type'], 'CompressedData');
      expect(snapshot['compressed_format'], 'zlib');
      expect(snapshot['roundtrip'], 'payload');
    });
  });
}
