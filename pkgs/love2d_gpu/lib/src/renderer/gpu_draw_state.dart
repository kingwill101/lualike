import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:love2d/love2d.dart';

final Expando<_GpuDrawStateCache> _drawStateCaches =
    Expando<_GpuDrawStateCache>('love2d.gpuDrawStateCache');

void applyGpuDrawState(
  gpu.RenderPass pass,
  LoveDrawCommand command,
  ui.Size viewportSize,
) {
  final cache = _drawStateCaches[pass] ??= _GpuDrawStateCache();
  if (cache.shouldApplyBlend(command)) {
    _applyBlendState(pass, command);
    cache.recordBlend(command);
  }
  _applyStencilState(pass, command);
  if (cache.shouldApplyScissor(command.scissor, viewportSize)) {
    _applyScissor(pass, command.scissor, viewportSize);
    cache.recordScissor(command.scissor, viewportSize);
  }
}

final class _GpuDrawStateCache {
  bool _blendInitialized = false;
  bool _blendEnabled = false;
  LoveGraphicsBlendMode? _blendMode;
  LoveGraphicsBlendAlphaMode? _blendAlphaMode;

  bool _scissorInitialized = false;
  LoveScissorRect? _scissor;
  int _viewportWidth = 0;
  int _viewportHeight = 0;

  bool shouldApplyBlend(LoveDrawCommand command) {
    final enabled =
        command.blendMode != LoveGraphicsBlendMode.replace &&
        command.blendMode != LoveGraphicsBlendMode.none;
    return !_blendInitialized ||
        enabled != _blendEnabled ||
        (enabled &&
            (command.blendMode != _blendMode ||
                command.blendAlphaMode != _blendAlphaMode));
  }

  void recordBlend(LoveDrawCommand command) {
    _blendInitialized = true;
    _blendEnabled =
        command.blendMode != LoveGraphicsBlendMode.replace &&
        command.blendMode != LoveGraphicsBlendMode.none;
    _blendMode = command.blendMode;
    _blendAlphaMode = command.blendAlphaMode;
  }

  bool shouldApplyScissor(
    LoveScissorRect? scissor,
    ui.Size viewportSize,
  ) {
    return !_scissorInitialized ||
        scissor != _scissor ||
        viewportSize.width.ceil() != _viewportWidth ||
        viewportSize.height.ceil() != _viewportHeight;
  }

  void recordScissor(LoveScissorRect? scissor, ui.Size viewportSize) {
    _scissorInitialized = true;
    _scissor = scissor;
    _viewportWidth = viewportSize.width.ceil();
    _viewportHeight = viewportSize.height.ceil();
  }
}

void _applyBlendState(gpu.RenderPass pass, LoveDrawCommand command) {
  final blendMode = command.blendMode;
  final sourceColorBlendFactor =
      command.blendAlphaMode == LoveGraphicsBlendAlphaMode.premultiplied
      ? gpu.BlendFactor.one
      : gpu.BlendFactor.sourceAlpha;

  if (blendMode == LoveGraphicsBlendMode.replace ||
      blendMode == LoveGraphicsBlendMode.none) {
    pass.setColorBlendEnable(false);
    return;
  }

  pass.setColorBlendEnable(true);

  if (blendMode == LoveGraphicsBlendMode.alpha) {
    pass.setColorBlendEquation(
      gpu.ColorBlendEquation(
        colorBlendOperation: gpu.BlendOperation.add,
        sourceColorBlendFactor: sourceColorBlendFactor,
        destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
        alphaBlendOperation: gpu.BlendOperation.add,
        sourceAlphaBlendFactor: gpu.BlendFactor.one,
        destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
      ),
    );
  } else if (blendMode == LoveGraphicsBlendMode.add) {
    pass.setColorBlendEquation(
      gpu.ColorBlendEquation(
        colorBlendOperation: gpu.BlendOperation.add,
        sourceColorBlendFactor: sourceColorBlendFactor,
        destinationColorBlendFactor: gpu.BlendFactor.one,
        alphaBlendOperation: gpu.BlendOperation.add,
        // Additive color modes preserve the destination alpha in LOVE.
        sourceAlphaBlendFactor: gpu.BlendFactor.zero,
        destinationAlphaBlendFactor: gpu.BlendFactor.one,
      ),
    );
  } else if (blendMode == LoveGraphicsBlendMode.subtract) {
    pass.setColorBlendEquation(
      gpu.ColorBlendEquation(
        colorBlendOperation: gpu.BlendOperation.reverseSubtract,
        sourceColorBlendFactor: sourceColorBlendFactor,
        destinationColorBlendFactor: gpu.BlendFactor.one,
        alphaBlendOperation: gpu.BlendOperation.add,
        // Match the Canvas rasterizer: subtraction does not change alpha.
        sourceAlphaBlendFactor: gpu.BlendFactor.zero,
        destinationAlphaBlendFactor: gpu.BlendFactor.one,
      ),
    );
  } else if (blendMode == LoveGraphicsBlendMode.multiply) {
    pass.setColorBlendEquation(
      gpu.ColorBlendEquation(
        colorBlendOperation: gpu.BlendOperation.add,
        sourceColorBlendFactor: gpu.BlendFactor.destinationColor,
        destinationColorBlendFactor: gpu.BlendFactor.zero,
        alphaBlendOperation: gpu.BlendOperation.add,
        sourceAlphaBlendFactor: gpu.BlendFactor.destinationAlpha,
        destinationAlphaBlendFactor: gpu.BlendFactor.zero,
      ),
    );
  } else if (blendMode == LoveGraphicsBlendMode.screen) {
    pass.setColorBlendEquation(
      gpu.ColorBlendEquation(
        colorBlendOperation: gpu.BlendOperation.add,
        sourceColorBlendFactor: sourceColorBlendFactor,
        destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceColor,
        alphaBlendOperation: gpu.BlendOperation.add,
        sourceAlphaBlendFactor: gpu.BlendFactor.one,
        destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
      ),
    );
  } else {
    pass.setColorBlendEnable(false);
  }
}

void _applyStencilState(gpu.RenderPass pass, LoveDrawCommand command) {
  if (command is LoveStencilClearCommand) {
    pass.setStencilReference(command.value);
    pass.setStencilConfig(
      gpu.StencilConfig(
        compareFunction: gpu.CompareFunction.always,
        stencilFailureOperation: gpu.StencilOperation.keep,
        depthFailureOperation: gpu.StencilOperation.keep,
        depthStencilPassOperation: gpu.StencilOperation.setToReferenceValue,
        readMask: 0xFFFFFFFF,
        writeMask: 0xFFFFFFFF,
      ),
      targetFace: gpu.StencilFace.both,
    );
    return;
  }

  final stencilAction = command.stencilAction;
  if (stencilAction == null &&
      command.stencilCompare == LoveGraphicsCompareMode.always) {
    return;
  }

  pass.setStencilReference(command.stencilValue);
  pass.setStencilConfig(
    gpu.StencilConfig(
      compareFunction: _stencilCompareFunctionForLove(command.stencilCompare),
      stencilFailureOperation: gpu.StencilOperation.keep,
      depthFailureOperation: gpu.StencilOperation.keep,
      depthStencilPassOperation: stencilAction == null
          ? gpu.StencilOperation.keep
          : _stencilOperationForLove(stencilAction),
      readMask: 0xFFFFFFFF,
      writeMask: 0xFFFFFFFF,
    ),
    targetFace: gpu.StencilFace.both,
  );
}

gpu.CompareFunction _stencilCompareFunctionForLove(
  LoveGraphicsCompareMode mode,
) {
  return switch (mode) {
    LoveGraphicsCompareMode.equal => gpu.CompareFunction.equal,
    LoveGraphicsCompareMode.notequal => gpu.CompareFunction.notEqual,
    LoveGraphicsCompareMode.less => gpu.CompareFunction.less,
    LoveGraphicsCompareMode.lequal => gpu.CompareFunction.lessEqual,
    LoveGraphicsCompareMode.gequal => gpu.CompareFunction.greaterEqual,
    LoveGraphicsCompareMode.greater => gpu.CompareFunction.greater,
    LoveGraphicsCompareMode.never => gpu.CompareFunction.never,
    LoveGraphicsCompareMode.always => gpu.CompareFunction.always,
  };
}

gpu.StencilOperation _stencilOperationForLove(
  LoveGraphicsStencilAction action,
) {
  return switch (action) {
    LoveGraphicsStencilAction.replace =>
      gpu.StencilOperation.setToReferenceValue,
    LoveGraphicsStencilAction.increment => gpu.StencilOperation.incrementClamp,
    LoveGraphicsStencilAction.decrement => gpu.StencilOperation.decrementClamp,
    LoveGraphicsStencilAction.incrementWrap =>
      gpu.StencilOperation.incrementWrap,
    LoveGraphicsStencilAction.decrementWrap =>
      gpu.StencilOperation.decrementWrap,
    LoveGraphicsStencilAction.invert => gpu.StencilOperation.invert,
  };
}

void _applyScissor(
  gpu.RenderPass pass,
  LoveScissorRect? scissor,
  ui.Size viewportSize,
) {
  final x = scissor?.x.round() ?? 0;
  final y = scissor?.y.round() ?? 0;
  final width = scissor?.width.round() ?? viewportSize.width.ceil();
  final height = scissor?.height.round() ?? viewportSize.height.ceil();
  pass.setScissor(gpu.Scissor(x: x, y: y, width: width, height: height));
}
