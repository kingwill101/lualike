import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

final List<({String name, String url, String destinationRelativePath})>
_assetPacks = <({String name, String url, String destinationRelativePath})>[
  (
    name: 'Roguelike/RPG Pack',
    url:
        'https://kenney.nl/media/pages/assets/roguelike-rpg-pack/1cb71b28fb-1677697420/kenney_roguelike-rpg-pack.zip',
    destinationRelativePath: 'art/kenney_roguelike_rpg_pack',
  ),
  (
    name: 'Roguelike Characters',
    url:
        'https://kenney.nl/media/pages/assets/roguelike-characters/cc364edf00-1729196490/kenney_roguelike-characters.zip',
    destinationRelativePath: 'art/kenney_roguelike_characters',
  ),
  (
    name: 'UI Pack - Pixel Adventure',
    url:
        'https://kenney.nl/media/pages/assets/ui-pack-pixel-adventure/16e3fc9e74-1729196257/kenney_ui-pack-pixel-adventure.zip',
    destinationRelativePath: 'art/kenney_ui_pack_pixel_adventure',
  ),
  (
    name: 'Input Prompts Pixel',
    url:
        'https://kenney.nl/media/pages/assets/input-prompts-pixel/4d8e1d0368-1774771309/kenney_input-prompts-pixel.zip',
    destinationRelativePath: 'art/kenney_input_prompts_pixel',
  ),
  (
    name: 'Minimap Pack',
    url:
        'https://kenney.nl/media/pages/assets/minimap-pack/1fb256c40f-1730884114/kenney_minimap-pack.zip',
    destinationRelativePath: 'art/kenney_minimap_pack',
  ),
  (
    name: 'Light Masks',
    url:
        'https://kenney.nl/media/pages/assets/light-masks/721303e893-1775631687/kenney_light-masks-1.0.zip',
    destinationRelativePath: 'art/kenney_light_masks',
  ),
  (
    name: 'Impact Sounds',
    url:
        'https://kenney.nl/media/pages/assets/impact-sounds/8aa7b545c9-1677589768/kenney_impact-sounds.zip',
    destinationRelativePath: 'audio/kenney_impact_sounds',
  ),
  (
    name: 'UI Audio',
    url:
        'https://kenney.nl/media/pages/assets/ui-audio/e19c9b1814-1677590494/kenney_ui-audio.zip',
    destinationRelativePath: 'audio/kenney_ui_audio',
  ),
  (
    name: 'Music Jingles',
    url:
        'https://kenney.nl/media/pages/assets/music-jingles/4f5dd770b7-1677590399/kenney_music-jingles.zip',
    destinationRelativePath: 'audio/kenney_music_jingles',
  ),
  (
    name: 'Kenney Fonts',
    url:
        'https://kenney.nl/media/pages/assets/kenney-fonts/3492f8d47e-1677661710/kenney_kenney-fonts.zip',
    destinationRelativePath: 'fonts/kenney_fonts',
  ),
];

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final packageRoot = p.normalize(
    p.join(p.dirname(Platform.script.toFilePath()), '..'),
  );
  final exampleRoot = p.join(packageRoot, 'example');
  final assetRoot = p.join(exampleRoot, 'assets', 'relic_breach');
  final downloadRoot = p.join(exampleRoot, 'build', 'relic_breach_downloads');

  await Directory(downloadRoot).create(recursive: true);

  stdout.writeln('Syncing Relic Breach assets into $assetRoot');
  for (final pack in _assetPacks) {
    await _syncPack(
      pack: pack,
      assetRoot: assetRoot,
      downloadRoot: downloadRoot,
      force: force,
    );
  }
  stdout.writeln('Relic Breach asset sync complete.');
}

Future<void> _syncPack({
  required ({String name, String url, String destinationRelativePath}) pack,
  required String assetRoot,
  required String downloadRoot,
  required bool force,
}) async {
  final archivePath = p.join(downloadRoot, p.basename(pack.url));
  final destinationPath = p.join(assetRoot, pack.destinationRelativePath);
  final destinationDirectory = Directory(destinationPath);

  stdout.writeln('');
  stdout.writeln('== ${pack.name} ==');
  stdout.writeln(pack.url);

  if (force && await destinationDirectory.exists()) {
    stdout.writeln('Removing existing directory $destinationPath');
    await destinationDirectory.delete(recursive: true);
  }
  await destinationDirectory.create(recursive: true);

  await _downloadToFile(pack.url, archivePath);
  await _extractZip(archivePath, destinationPath);
}

Future<void> _downloadToFile(String url, String destinationPath) async {
  stdout.writeln('Downloading ${p.basename(destinationPath)}');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Failed to download $url (status ${response.statusCode})',
        uri: Uri.parse(url),
      );
    }

    final sink = File(destinationPath).openWrite();
    await response.forEach(sink.add);
    await sink.close();
  } finally {
    client.close(force: true);
  }
}

Future<void> _extractZip(String archivePath, String destinationPath) async {
  stdout.writeln('Extracting into $destinationPath');
  final bytes = await File(archivePath).readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);

  for (final entry in archive) {
    final entryPath = p.normalize(
      p.join(destinationPath, p.fromUri(entry.name)),
    );
    if (!p.isWithin(destinationPath, entryPath) &&
        entryPath != destinationPath) {
      throw StateError(
        'Refusing to extract outside destination: ${entry.name}',
      );
    }

    if (entry.isFile) {
      final outputFile = File(entryPath);
      await outputFile.parent.create(recursive: true);
      final fileBytes = entry.readBytes();
      if (fileBytes == null) {
        throw StateError('Archive entry had no file data: ${entry.name}');
      }
      await outputFile.writeAsBytes(fileBytes, flush: true);
    } else {
      await Directory(entryPath).create(recursive: true);
    }
  }
}
