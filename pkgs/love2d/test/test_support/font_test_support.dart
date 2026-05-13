import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:path/path.dart' as p;

import 'package_path_test_support.dart';

const String love2dDefaultTrueTypeFontAssetPath =
    'packages/love2d/third_party/love/extra/resources/Vera.ttf';

Future<Directory> love2dResourceDirectory() async {
  final packageRoot = await love2dPackageRoot();
  return Directory(
    p.join(packageRoot.path, 'third_party', 'love', 'extra', 'resources'),
  );
}

Future<File> love2dVeraFontFile() async {
  final resources = await love2dResourceDirectory();
  return File(p.join(resources.path, 'Vera.ttf'));
}

Future<void> ensureLove2dDefaultFontAssetAvailable() async {
  try {
    await rootBundle.load(love2dDefaultTrueTypeFontAssetPath);
    return;
  } catch (_) {
    // Workspace-root flutter test runs do not always expose package assets.
  }

  final fontBytes = await (await love2dVeraFontFile()).readAsBytes();
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
    ByteData? message,
  ) async {
    if (message == null) {
      return null;
    }

    final key = utf8.decode(
      message.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes),
    );
    if (key != love2dDefaultTrueTypeFontAssetPath) {
      return null;
    }

    return ByteData.sublistView(fontBytes);
  });
}

void clearLove2dTestAssetMocks() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', null);
}

const String bmFontDefinition = '''
info face="Test" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
common lineHeight=6 base=5 scaleW=8 scaleH=6 pages=1 packed=0
page id=0 file="page.png"
chars count=2
char id=65 x=0 y=0 width=3 height=6 xoffset=0 yoffset=0 xadvance=4 page=0 chnl=15
char id=66 x=3 y=0 width=2 height=6 xoffset=0 yoffset=0 xadvance=3 page=0 chnl=15
kernings count=1
kerning first=65 second=66 amount=-1
''';

Uint8List imageFontStripBytes() {
  final bytes = Uint8List(9 * 6 * 4);

  void fillColumns(int start, int end, List<int> rgba) {
    for (var row = 0; row < 6; row++) {
      for (var column = start; column < end; column++) {
        final offset = ((row * 9) + column) * 4;
        bytes[offset] = rgba[0];
        bytes[offset + 1] = rgba[1];
        bytes[offset + 2] = rgba[2];
        bytes[offset + 3] = rgba[3];
      }
    }
  }

  fillColumns(0, 1, const <int>[255, 0, 255, 255]);
  fillColumns(1, 3, const <int>[255, 255, 255, 255]);
  fillColumns(3, 4, const <int>[255, 0, 255, 255]);
  fillColumns(4, 5, const <int>[255, 96, 96, 255]);
  fillColumns(5, 6, const <int>[255, 0, 255, 255]);
  fillColumns(6, 9, const <int>[96, 255, 96, 255]);
  return bytes;
}

Uint8List requireLuaStringBytes(Object? value) {
  final raw = value is Value ? value.raw : value;
  return switch (raw) {
    final LuaString stringValue => stringValue.bytes,
    _ => throw TestFailure('Expected a LuaString result'),
  };
}
