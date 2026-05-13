import 'dart:io';

import 'package:media_kit/media_kit.dart';

Future<void> main() async {
  MediaKit.ensureInitialized();

  final sample = File(
    'example/assets/love_example_browser/assets/HA-1112-M1LBuchon_flyby.ogg',
  );
  final player = Player(
    configuration: const PlayerConfiguration(
      muted: true,
      title: 'LuaLike media_kit probe',
    ),
  );

  try {
    await player.open(Media(sample.path));
    stdout.writeln('opened=${sample.path}');
    stdout.writeln('track.video=${player.state.track.video}');
    stdout.writeln('tracks.video=${player.state.tracks.video}');
    stdout.writeln('track.audio=${player.state.track.audio}');
    stdout.writeln('tracks.audio=${player.state.tracks.audio}');
    stdout.writeln('size=${player.state.width}x${player.state.height}');

    await Future<void>.delayed(const Duration(seconds: 5));
    stdout.writeln('after_delay.track.video=${player.state.track.video}');
    stdout.writeln('after_delay.tracks.video=${player.state.tracks.video}');
    stdout.writeln(
      'after_delay.size=${player.state.width}x${player.state.height}',
    );

    if (player.state.tracks.video.length > 2) {
      final selected = player.state.tracks.video.last;
      stdout.writeln('selecting_video_track=$selected');
      await player.setVideoTrack(selected);
      await Future<void>.delayed(const Duration(seconds: 2));
      stdout.writeln('after_select.track.video=${player.state.track.video}');
      stdout.writeln(
        'after_select.size=${player.state.width}x${player.state.height}',
      );
    }

    final png = await player.screenshot(format: 'image/png');
    stdout.writeln('png_bytes=${png?.length ?? 0}');
    if (png != null && png.isNotEmpty) {
      await File('/tmp/media_kit_probe.png').writeAsBytes(png);
      stdout.writeln('wrote=/tmp/media_kit_probe.png');
    }
  } finally {
    await player.dispose();
  }
}
