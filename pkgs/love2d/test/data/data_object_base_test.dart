import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('Data and Object base methods', () {
    test(
      'ByteData and FileData expose shared pointer and object helpers',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}

local byte = love.data.newByteData("hello")
local view = love.data.newDataView(byte, 1, 3)
local file = love.filesystem.newFileData("payload", "payload.bin")
local clone = byte:clone()

testbed.byte_same_pointer = byte:getPointer() == byte:getFFIPointer()
testbed.view_has_ffi_pointer = view:getFFIPointer() ~= nil
testbed.file_same_pointer = file:getPointer() == file:getFFIPointer()
testbed.byte_size = byte:getSize()
testbed.byte_string = byte:getString()
testbed.file_size = file:getSize()
testbed.file_string = file:getString()
testbed.clone_type = clone:type()
testbed.byte_typeof_data = byte:typeOf("Data")
testbed.byte_typeof_object = byte:typeOf("Object")
testbed.file_type = file:type()
testbed.file_typeof_data = file:typeOf("Data")
testbed.file_typeof_object = file:typeOf("Object")
testbed.byte_release_first = byte:release()
testbed.byte_release_second = byte:release()
testbed.file_release_first = file:release()
testbed.file_release_second = file:release()
''');

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['byte_same_pointer'], isTrue);
        expect(snapshot['view_has_ffi_pointer'], isTrue);
        expect(snapshot['file_same_pointer'], isTrue);
        expect(snapshot['byte_size'], 5);
        expect(snapshot['byte_string'], 'hello');
        expect(snapshot['file_size'], 7);
        expect(snapshot['file_string'], 'payload');
        expect(snapshot['clone_type'], 'ByteData');
        expect(snapshot['byte_typeof_data'], isTrue);
        expect(snapshot['byte_typeof_object'], isTrue);
        expect(snapshot['file_type'], 'FileData');
        expect(snapshot['file_typeof_data'], isTrue);
        expect(snapshot['file_typeof_object'], isTrue);
        expect(snapshot['byte_release_first'], isTrue);
        expect(snapshot['byte_release_second'], isFalse);
        expect(snapshot['file_release_first'], isTrue);
        expect(snapshot['file_release_second'], isFalse);
      },
    );

    test(
      'compat FileData values route Data:clone through the shared runtime binding',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}

local image = love.image.newImageData(1, 1)
image:setPixel(0, 0, 1, 0.5, 0.25, 1)
local encoded = image:encode("png")
local clone = encoded:clone()

testbed.encoded_type = encoded:type()
testbed.clone_type = clone:type()
testbed.clone_typeof_data = clone:typeOf("Data")
testbed.clone_size = clone:getSize()
testbed.clone_string_matches = clone:getString() == encoded:getString()
''');

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['encoded_type'], 'FileData');
        expect(snapshot['clone_type'], 'FileData');
        expect(snapshot['clone_typeof_data'], isTrue);
        expect(snapshot['clone_size'], greaterThan(0));
        expect(snapshot['clone_string_matches'], isTrue);
      },
    );
  });
}
