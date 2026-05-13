import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

const int _tileSize = 16;
const int _margin = 1;
const int _padding = 8;
const int _columnsPerSheet = 10;
const int _labelHeight = 10;

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/render_relic_breach_spritesheet_index.dart '
      '<relative spritesheet path> [output file]',
    );
    exitCode = 64;
    return;
  }

  final packageRoot = p.normalize(
    p.join(p.dirname(Platform.script.toFilePath()), '..'),
  );
  final inputFile = File(p.join(packageRoot, args[0]));
  if (!await inputFile.exists()) {
    stderr.writeln('Spritesheet not found: ${inputFile.path}');
    exitCode = 1;
    return;
  }

  final outputPath = args.length > 1
      ? p.join(packageRoot, args[1])
      : p.join(
          packageRoot,
          'example',
          'build',
          'spritesheet_index_${p.basenameWithoutExtension(inputFile.path)}.png',
        );

  final decoded = img.decodeImage(await inputFile.readAsBytes());
  if (decoded == null) {
    stderr.writeln('Failed to decode spritesheet: ${inputFile.path}');
    exitCode = 1;
    return;
  }

  final source = decoded.convert(format: img.Format.uint8, numChannels: 4);
  final columns = ((source.width + _margin) / (_tileSize + _margin)).floor();
  final rows = ((source.height + _margin) / (_tileSize + _margin)).floor();
  final tiles = <({String label, img.Image tile})>[];

  for (var row = 0; row < rows; row++) {
    for (var column = 0; column < columns; column++) {
      final x = column * (_tileSize + _margin);
      final y = row * (_tileSize + _margin);
      final tile = img.copyCrop(
        source,
        x: x,
        y: y,
        width: _tileSize,
        height: _tileSize,
      );
      tiles.add((label: '${column + 1},${row + 1}', tile: tile));
    }
  }

  final annotated = _composeContactSheet(tiles);

  final outputFile = File(outputPath);
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsBytes(img.encodePng(annotated), flush: true);
  stdout.writeln('Wrote indexed spritesheet to $outputPath');
}

img.Image _composeContactSheet(List<({String label, img.Image tile})> tiles) {
  final columns = _columnsPerSheet;
  final rows = (tiles.length / columns).ceil();
  final cellWidth = _tileSize + _padding * 2;
  final cellHeight = _tileSize + _labelHeight + _padding * 2;
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
      tile.tile,
      dstX: originX + _padding,
      dstY: originY + _padding,
    );
    img.drawString(
      sheet,
      tile.label,
      font: img.arial14,
      x: originX + 2,
      y: originY + _tileSize + _padding + 1,
      color: img.ColorRgba8(255, 239, 184, 255),
    );
  }

  return sheet;
}
