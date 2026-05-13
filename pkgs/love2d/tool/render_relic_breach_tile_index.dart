import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

const int _defaultTileSize = 16;
const int _defaultPadding = 8;
const int _defaultColumns = 10;
const int _labelHeight = 10;

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/render_relic_breach_tile_index.dart '
      '<relative tile directory> [output file]',
    );
    exitCode = 64;
    return;
  }

  final packageRoot = p.normalize(
    p.join(p.dirname(Platform.script.toFilePath()), '..'),
  );
  final tileDirectory = Directory(p.join(packageRoot, args[0]));
  if (!await tileDirectory.exists()) {
    stderr.writeln('Tile directory not found: ${tileDirectory.path}');
    exitCode = 1;
    return;
  }

  final outputPath = args.length > 1
      ? p.join(packageRoot, args[1])
      : p.join(
          packageRoot,
          'example',
          'build',
          'tile_index_${p.basename(tileDirectory.path)}.png',
        );

  final tiles = await _loadTiles(tileDirectory);
  if (tiles.isEmpty) {
    stderr.writeln('No tile_*.png files found in ${tileDirectory.path}');
    exitCode = 1;
    return;
  }

  final sheet = _composeTileIndexSheet(tiles);
  final outputFile = File(outputPath);
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsBytes(img.encodePng(sheet), flush: true);
  stdout.writeln('Wrote ${tiles.length} tiles to $outputPath');
}

Future<List<_IndexedTile>> _loadTiles(Directory directory) async {
  final files = await directory
      .list()
      .where((entity) => entity is File)
      .cast<File>()
      .where(
        (file) =>
            p.basename(file.path).startsWith('tile_') &&
            p.extension(file.path) == '.png',
      )
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));

  final tiles = <_IndexedTile>[];
  for (final file in files) {
    final match = RegExp(r'tile_(\d+)\.png$').firstMatch(file.path);
    if (match == null) {
      continue;
    }

    final image = img.decodePng(await file.readAsBytes());
    if (image == null) {
      continue;
    }

    tiles.add(
      _IndexedTile(
        index: int.parse(match.group(1)!),
        image: image.convert(format: img.Format.uint8, numChannels: 4),
      ),
    );
  }
  return tiles;
}

img.Image _composeTileIndexSheet(List<_IndexedTile> tiles) {
  final columns = _defaultColumns;
  final rows = (tiles.length / columns).ceil();
  final cellWidth = _defaultTileSize + _defaultPadding * 2;
  final cellHeight = _defaultTileSize + _labelHeight + _defaultPadding * 2;
  final sheet = img.Image(
    width: columns * cellWidth,
    height: rows * cellHeight,
    numChannels: 4,
  );

  img.fill(sheet, color: img.ColorRgba8(12, 16, 28, 255));

  for (var i = 0; i < tiles.length; i++) {
    final tile = tiles[i];
    final column = i % columns;
    final row = i ~/ columns;
    final originX = column * cellWidth;
    final originY = row * cellHeight;

    img.fillRect(
      sheet,
      x1: originX + 1,
      y1: originY + 1,
      x2: originX + cellWidth - 2,
      y2: originY + cellHeight - 2,
      color: img.ColorRgba8(28, 35, 56, 255),
    );

    img.compositeImage(
      sheet,
      tile.image,
      dstX: originX + _defaultPadding,
      dstY: originY + _defaultPadding,
    );

    img.drawString(
      sheet,
      tile.index.toString(),
      font: img.arial14,
      x: originX + 2,
      y: originY + _defaultTileSize + _defaultPadding + 1,
      color: img.ColorRgba8(232, 238, 252, 255),
    );
  }

  return sheet;
}

class _IndexedTile {
  const _IndexedTile({required this.index, required this.image});

  final int index;
  final img.Image image;
}
