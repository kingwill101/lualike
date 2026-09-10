import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

const int _atlasWidth = 256;

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/pack_native_default_font.dart '
      '<native-export-directory> [output-directory]',
    );
    exitCode = 64;
    return;
  }

  final packageRoot = p.normalize(
    p.join(p.dirname(Platform.script.toFilePath()), '..'),
  );
  final exportDirectory = Directory(p.normalize(args.first));
  final outputDirectory = Directory(
    args.length == 2
        ? p.normalize(args[1])
        : p.join(
            packageRoot,
            'third_party',
            'love',
            'extra',
            'resources',
            'default_font',
          ),
  );
  if (!await exportDirectory.exists()) {
    stderr.writeln(
      'Native export directory does not exist: ${exportDirectory.path}',
    );
    exitCode = 66;
    return;
  }

  final font = await _readFont(File(p.join(exportDirectory.path, 'font.tsv')));
  final glyphs = await _readGlyphs(
    File(p.join(exportDirectory.path, 'glyphs.tsv')),
  );
  final kernings = await _readKernings(
    File(p.join(exportDirectory.path, 'kerning.tsv')),
  );

  var cursorX = 1;
  var cursorY = 1;
  var rowHeight = 0;
  final packed = <Map<String, Object>>[];
  for (final glyph in glyphs) {
    final width = glyph['width']! as int;
    final height = glyph['height']! as int;
    var x = 0;
    var y = 0;
    if (width > 0 && height > 0) {
      if (cursorX + width + 1 > _atlasWidth) {
        cursorX = 1;
        cursorY += rowHeight + 1;
        rowHeight = 0;
      }
      x = cursorX;
      y = cursorY;
      cursorX += width + 1;
      rowHeight = height > rowHeight ? height : rowHeight;
    }
    packed.add(<String, Object>{...glyph, 'x': x, 'y': y});
  }

  final atlasHeight = cursorY + rowHeight + 1;
  final atlas = img.Image(
    width: _atlasWidth,
    height: atlasHeight,
    numChannels: 4,
  );
  for (final glyph in packed) {
    final codepoint = glyph['codepoint']! as int;
    final width = glyph['width']! as int;
    final height = glyph['height']! as int;
    if (width == 0 || height == 0) {
      continue;
    }
    final bytes = await File(
      p.join(
        exportDirectory.path,
        'glyphs',
        '${codepoint.toString().padLeft(3, '0')}.la8',
      ),
    ).readAsBytes();
    final expectedLength = width * height * 2;
    if (bytes.length != expectedLength) {
      throw FormatException(
        'Glyph $codepoint has ${bytes.length} bytes; expected $expectedLength.',
      );
    }
    final atlasX = glyph['x']! as int;
    final atlasY = glyph['y']! as int;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final sourceOffset = ((y * width) + x) * 2;
        final luminance = bytes[sourceOffset];
        final alpha = bytes[sourceOffset + 1];
        atlas.setPixelRgba(
          atlasX + x,
          atlasY + y,
          luminance,
          luminance,
          luminance,
          alpha,
        );
      }
    }
  }

  await outputDirectory.create(recursive: true);
  final basename = 'Vera-12-normal-1x';
  final pngFile = File(p.join(outputDirectory.path, '$basename.png'));
  final jsonFile = File(p.join(outputDirectory.path, '$basename.json'));
  await pngFile.writeAsBytes(img.encodePng(atlas), flush: true);
  final metadataJson = const JsonEncoder.withIndent('  ').convert(
    <String, Object>{
      'schemaVersion': 1,
      'generator': 'LOVE 11.5 love.font.newTrueTypeRasterizer',
      'font': font,
      'atlas': <String, Object>{'width': _atlasWidth, 'height': atlasHeight},
      'glyphs': packed,
      'kernings': kernings,
    },
  );
  await jsonFile.writeAsString('$metadataJson\n', flush: true);
  stdout.writeln(
    'Packed ${glyphs.length} native LOVE glyphs into '
    '${pngFile.path} (${_atlasWidth}x$atlasHeight)',
  );
  stdout.writeln('Wrote ${kernings.length} kerning pairs to ${jsonFile.path}');
}

Future<Map<String, Object>> _readFont(File file) async {
  final fields = _dataLines(await file.readAsLines()).single.split('\t');
  if (fields.length != 7) {
    throw const FormatException('font.tsv must contain seven fields.');
  }
  return <String, Object>{
    'size': int.parse(fields[0]),
    'dpiScale': double.parse(fields[1]),
    'hinting': fields[2],
    'height': int.parse(fields[3]),
    'ascent': int.parse(fields[4]),
    'descent': int.parse(fields[5]),
    'lineHeight': int.parse(fields[6]),
  };
}

Future<List<Map<String, Object>>> _readGlyphs(File file) async {
  return <Map<String, Object>>[
    for (final line in _dataLines(await file.readAsLines()))
      switch (line.split('\t')) {
        [
          final codepoint,
          final width,
          final height,
          final advance,
          final bearingX,
          final bearingY,
        ] =>
          <String, Object>{
            'codepoint': int.parse(codepoint),
            'width': int.parse(width),
            'height': int.parse(height),
            'advance': int.parse(advance),
            'bearingX': int.parse(bearingX),
            'bearingY': int.parse(bearingY),
          },
        _ => throw FormatException('Malformed glyph line: $line'),
      },
  ];
}

Future<List<Map<String, Object>>> _readKernings(File file) async {
  return <Map<String, Object>>[
    for (final line in _dataLines(await file.readAsLines()))
      switch (line.split('\t')) {
        [final left, final right, final value] => <String, Object>{
          'left': int.parse(left),
          'right': int.parse(right),
          'value': double.parse(value),
        },
        _ => throw FormatException('Malformed kerning line: $line'),
      },
  ];
}

Iterable<String> _dataLines(List<String> lines) => lines
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty && !line.startsWith('#'));
