import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;

import '../love_runtime.dart';
import 'love_flame_harness_renderer.dart';
import 'love_flame_live_video_overlay_geometry.dart';
import 'love_flame_viewport_geometry.dart';

sealed class LoveFlameLiveVideoOverlayEntry {
  const LoveFlameLiveVideoOverlayEntry();
}

final class LoveFlameLiveVideoOverlayVideoEntry
    extends LoveFlameLiveVideoOverlayEntry {
  const LoveFlameLiveVideoOverlayVideoEntry(this.command);

  final LoveVideoCommand command;
}

final class LoveFlameLiveVideoOverlaySurfaceEntry
    extends LoveFlameLiveVideoOverlayEntry {
  const LoveFlameLiveVideoOverlaySurfaceEntry(this.snapshot);

  final LoveGraphicsSurfaceSnapshot snapshot;
}

List<LoveFlameLiveVideoOverlayEntry> buildLoveFlameLiveVideoOverlayEntries(
  LoveGraphicsSurfaceSnapshot surface,
) {
  final entries = <LoveFlameLiveVideoOverlayEntry>[];
  var sawLiveVideo = false;
  var overlayCommands = <LoveDrawCommand>[];

  void flushOverlayCommands() {
    if (!sawLiveVideo || overlayCommands.isEmpty) {
      overlayCommands = <LoveDrawCommand>[];
      return;
    }

    entries.add(
      LoveFlameLiveVideoOverlaySurfaceEntry(
        LoveGraphicsSurfaceSnapshot(
          clearColor: const LoveColor(0, 0, 0, 0),
          clearColorMask: LoveGraphicsColorMask.all,
          clearStencil: 0,
          clearScissor: null,
          commands: List<LoveDrawCommand>.unmodifiable(overlayCommands),
        ),
      ),
    );
    overlayCommands = <LoveDrawCommand>[];
  }

  for (final command in surface.commands) {
    if (command is LoveVideoCommand) {
      flushOverlayCommands();
      entries.add(LoveFlameLiveVideoOverlayVideoEntry(command));
      sawLiveVideo = true;
      continue;
    }

    if (sawLiveVideo) {
      overlayCommands.add(command);
    }
  }

  flushOverlayCommands();
  return entries;
}

class LoveFlameLiveVideoOverlay extends StatelessWidget {
  const LoveFlameLiveVideoOverlay({
    super.key,
    required this.presentedFrameListenable,
    required this.windowMetricsProvider,
  });

  final ValueListenable<LoveGraphicsSurfaceSnapshot> presentedFrameListenable;
  final LoveWindowMetrics Function() windowMetricsProvider;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final windowMetrics = _resolveWindowMetrics(viewportSize);
        final destinationRect = loveViewportDestinationRect(
          windowMetrics: windowMetrics,
          viewportSize: viewportSize,
        );
        final logicalViewportSize = loveLogicalViewportSize(
          windowMetrics: windowMetrics,
          viewportSize: viewportSize,
        );
        if (destinationRect.width <= 0 ||
            destinationRect.height <= 0 ||
            logicalViewportSize.width <= 0 ||
            logicalViewportSize.height <= 0) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<LoveGraphicsSurfaceSnapshot>(
          valueListenable: presentedFrameListenable,
          builder: (context, surface, _) {
            final entries = buildLoveFlameLiveVideoOverlayEntries(surface);
            if (entries.isEmpty) {
              return const SizedBox.shrink();
            }

            return IgnorePointer(
              child: Stack(
                children: [
                  Positioned.fromRect(
                    rect: destinationRect,
                    child: ClipRect(
                      child: FittedBox(
                        fit: BoxFit.fill,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: logicalViewportSize.width,
                          height: logicalViewportSize.height,
                          child: Stack(
                            children: [
                              for (final entry in entries)
                                switch (entry) {
                                  final LoveFlameLiveVideoOverlayVideoEntry
                                  video =>
                                    _LoveLiveVideoTextureLayer(
                                      command: video.command,
                                    ),
                                  final LoveFlameLiveVideoOverlaySurfaceEntry
                                  segment =>
                                    Positioned.fill(
                                      child: RepaintBoundary(
                                        child: CustomPaint(
                                          painter: LoveSurfaceSnapshotPainter(
                                            snapshot: segment.snapshot,
                                            viewportSize: logicalViewportSize,
                                          ),
                                        ),
                                      ),
                                    ),
                                },
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  LoveWindowMetrics _resolveWindowMetrics(Size viewportSize) {
    try {
      return windowMetricsProvider();
    } on AssertionError {
      return LoveWindowMetrics(
        width: viewportSize.width.round(),
        height: viewportSize.height.round(),
        desktopWidth: viewportSize.width.round(),
        desktopHeight: viewportSize.height.round(),
      );
    }
  }
}

class _LoveLiveVideoTextureLayer extends StatelessWidget {
  const _LoveLiveVideoTextureLayer({required this.command});

  final LoveVideoCommand command;

  @override
  Widget build(BuildContext context) {
    final handle = command.video.livePresentationHandle;
    final controller = handle is media_kit_video.VideoController
        ? handle
        : null;
    final geometry = computeLoveFlameLiveVideoOverlayGeometry(command);
    if (controller == null || geometry == null) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          controller.id,
          controller.rect,
        ]),
        builder: (context, _) {
          final textureId = controller.id.value;
          final textureRect = controller.rect.value;
          if (textureId == null ||
              textureRect == null ||
              textureRect.width <= 0 ||
              textureRect.height <= 0) {
            return const SizedBox.shrink();
          }

          Widget texture = SizedBox(
            width: geometry.contentSize.width,
            height: geometry.contentSize.height,
            child: FittedBox(
              fit: BoxFit.fill,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: textureRect.width,
                height: textureRect.height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Texture(
                        textureId: textureId,
                        filterQuality:
                            loveFilterQualityForGraphicsDefaultFilter(
                              command.video.filter,
                            ),
                      ),
                    ),
                    if (textureRect.width <= 1.0 && textureRect.height <= 1.0)
                      const Positioned.fill(
                        child: ColoredBox(color: Colors.black),
                      ),
                  ],
                ),
              ),
            ),
          );
          if (geometry.frameSize != geometry.contentSize ||
              geometry.contentOffset != Offset.zero) {
            texture = SizedBox(
              width: geometry.frameSize.width,
              height: geometry.frameSize.height,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    left: geometry.contentOffset.dx,
                    top: geometry.contentOffset.dy,
                    width: geometry.contentSize.width,
                    height: geometry.contentSize.height,
                    child: texture,
                  ),
                ],
              ),
            );
          }
          if (geometry.hasRgbTint) {
            texture = ColorFiltered(
              colorFilter: ColorFilter.mode(
                geometry.rgbTintColor,
                BlendMode.modulate,
              ),
              child: texture,
            );
          }
          if (geometry.alpha < 1.0) {
            texture = Opacity(opacity: geometry.alpha, child: texture);
          }

          texture = Transform(
            alignment: Alignment.topLeft,
            transform: geometry.transform,
            child: texture,
          );
          if (geometry.scissorRect case final scissor?) {
            texture = ClipRect(
              clipper: _LoveRectClipper(scissor),
              child: texture,
            );
          }
          return texture;
        },
      ),
    );
  }
}

class _LoveRectClipper extends CustomClipper<Rect> {
  const _LoveRectClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) {
    return clampLoveFlameLiveVideoOverlayClipRect(rect, size);
  }

  @override
  bool shouldReclip(covariant _LoveRectClipper oldClipper) {
    return oldClipper.rect != rect;
  }
}
