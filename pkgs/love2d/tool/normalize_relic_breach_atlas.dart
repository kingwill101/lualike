import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

final List<
  ({String label, String sourceRelativePath, String destinationRelativePath})
>
_atlases = <({String label, String sourceRelativePath, String destinationRelativePath})>[
  (
    label: 'environment',
    sourceRelativePath:
        'example/assets/relic_breach/art/kenney_roguelike_rpg_pack/Spritesheet/roguelikeSheet_transparent.png',
    destinationRelativePath:
        'example/assets/relic_breach/art/kenney_roguelike_rpg_pack/Spritesheet/roguelikeSheet_runtime.png',
  ),
  (
    label: 'characters',
    sourceRelativePath:
        'example/assets/relic_breach/art/kenney_roguelike_characters/Spritesheet/roguelikeChar_transparent.png',
    destinationRelativePath:
        'example/assets/relic_breach/art/kenney_roguelike_characters/Spritesheet/roguelikeChar_runtime.png',
  ),
];

final List<
  ({String label, String sourceRelativePath, String destinationRelativePath})
>
_lightMasks = <({String label, String sourceRelativePath, String destinationRelativePath})>[
  (
    label: 'light circle mask',
    sourceRelativePath:
        'example/assets/relic_breach/art/kenney_light_masks/Default/circle_a_streaks.png',
    destinationRelativePath:
        'example/assets/relic_breach/art/kenney_light_masks/Default/circle_a_streaks_runtime.png',
  ),
  (
    label: 'light cone mask',
    sourceRelativePath:
        'example/assets/relic_breach/art/kenney_light_masks/Default/cone_a_blur.png',
    destinationRelativePath:
        'example/assets/relic_breach/art/kenney_light_masks/Default/cone_a_blur_runtime.png',
  ),
  (
    label: 'water caustics mask',
    sourceRelativePath:
        'example/assets/relic_breach/art/kenney_light_masks/Default/water_caustics_a.png',
    destinationRelativePath:
        'example/assets/relic_breach/art/kenney_light_masks/Default/water_caustics_a_runtime.png',
  ),
];

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final packageRoot = p.normalize(
    p.join(p.dirname(Platform.script.toFilePath()), '..'),
  );
  var failed = false;

  for (final atlas in _atlases) {
    final ok = await _normalizeImage(
      atlas,
      packageRoot: packageRoot,
      force: force,
      kind: 'atlas',
      normalize: _normalizeRgba,
    );
    failed = failed || !ok;
  }

  for (final mask in _lightMasks) {
    final ok = await _normalizeImage(
      mask,
      packageRoot: packageRoot,
      force: force,
      kind: 'mask',
      normalize: _normalizeLuminanceMask,
    );
    failed = failed || !ok;
  }

  if (failed) {
    exitCode = 1;
  }
}

Future<bool> _normalizeImage(
  ({String label, String sourceRelativePath, String destinationRelativePath})
  asset, {
  required String packageRoot,
  required bool force,
  required String kind,
  required img.Image Function(img.Image image) normalize,
}) async {
  final sourcePath = p.join(packageRoot, asset.sourceRelativePath);
  final destinationPath = p.join(packageRoot, asset.destinationRelativePath);

  final sourceFile = File(sourcePath);
  if (!await sourceFile.exists()) {
    stderr.writeln('Source ${asset.label} $kind not found: $sourcePath');
    return false;
  }

  final destinationFile = File(destinationPath);
  if (!force && await _isUpToDate(sourceFile, destinationFile)) {
    stdout.writeln('${asset.label} $kind already normalized: $destinationPath');
    return true;
  }

  final encodedSource = await sourceFile.readAsBytes();
  final decoded = img.decodeImage(encodedSource);
  if (decoded == null) {
    stderr.writeln('Failed to decode ${asset.label} $kind: $sourcePath');
    return false;
  }

  final normalized = normalize(decoded);

  await destinationFile.parent.create(recursive: true);
  await destinationFile.writeAsBytes(img.encodePng(normalized), flush: true);
  stdout.writeln(
    'Wrote normalized ${asset.label} $kind to $destinationPath '
    '(${normalized.width}x${normalized.height})',
  );
  return true;
}

img.Image _normalizeRgba(img.Image source) {
  return source.convert(
    format: img.Format.uint8,
    numChannels: 4,
    withPalette: false,
  );
}

img.Image _normalizeLuminanceMask(img.Image source) {
  final rgba = _normalizeRgba(source);
  final normalized = img.Image(
    width: rgba.width,
    height: rgba.height,
    numChannels: 4,
  );

  for (var y = 0; y < rgba.height; y++) {
    for (var x = 0; x < rgba.width; x++) {
      final pixel = rgba.getPixel(x, y);
      final luminance = (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114)
          .round();
      final alpha = (luminance * pixel.a / 255).round();
      normalized.setPixelRgba(x, y, 255, 255, 255, alpha);
    }
  }

  return normalized;
}

Future<bool> _isUpToDate(File sourceFile, File destinationFile) async {
  if (!await destinationFile.exists()) {
    return false;
  }

  final sourceStat = await sourceFile.stat();
  final destinationStat = await destinationFile.stat();
  return !destinationStat.modified.isBefore(sourceStat.modified);
}
