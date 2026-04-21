import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const String love2dDefaultTrueTypeFontAssetPath =
    'packages/love2d/third_party/love/extra/resources/Vera.ttf';

Future<Directory> love2dPackageRoot() async {
  final nestedSegments = <String>['pkgs', 'love2d'];
  final resourceSegments = <String>[
    'third_party',
    'love',
    'extra',
    'resources',
    'Vera.ttf',
  ];

  var current = Directory.current.absolute;
  while (true) {
    final directSegments = List<String>.from(resourceSegments)
      ..insert(0, current.path);
    final directCandidate = File(p.joinAll(directSegments));
    if (directCandidate.existsSync()) {
      return current;
    }

    final nestedPathSegments = List<String>.from(nestedSegments)
      ..insert(0, current.path);
    final nestedCandidate = Directory(p.joinAll(nestedPathSegments));
    final nestedResourceSegments = List<String>.from(resourceSegments)
      ..insert(0, nestedCandidate.path);
    if (File(p.joinAll(nestedResourceSegments)).existsSync()) {
      return nestedCandidate;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }

  throw StateError(
    'Unable to locate package:love2d test resources from '
    '${Directory.current.path}.',
  );
}

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
