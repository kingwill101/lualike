import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:love2d/love2d.dart';

void applyGpuDrawState(
  gpu.RenderPass pass,
  LoveDrawCommand command,
  ui.Size viewportSize,
) {
  _applyBlendState(pass, command);
  _applyStencilState(pass, command);
  _applyScissor(pass, command.scissor, viewportSize);
}

void _applyBlendState(gpu.RenderPass pass, LoveDrawCommand command) {
  final blendMode = command.blendMode;

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
        sourceColorBlendFactor: gpu.BlendFactor.one,
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
        sourceColorBlendFactor: gpu.BlendFactor.one,
        destinationColorBlendFactor: gpu.BlendFactor.one,
        alphaBlendOperation: gpu.BlendOperation.add,
        sourceAlphaBlendFactor: gpu.BlendFactor.one,
        destinationAlphaBlendFactor: gpu.BlendFactor.one,
      ),
    );
  } else if (blendMode == LoveGraphicsBlendMode.subtract) {
    pass.setColorBlendEquation(
      gpu.ColorBlendEquation(
        colorBlendOperation: gpu.BlendOperation.subtract,
        sourceColorBlendFactor: gpu.BlendFactor.one,
        destinationColorBlendFactor: gpu.BlendFactor.one,
        alphaBlendOperation: gpu.BlendOperation.subtract,
        sourceAlphaBlendFactor: gpu.BlendFactor.one,
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
        sourceAlphaBlendFactor: gpu.BlendFactor.one,
        destinationAlphaBlendFactor: gpu.BlendFactor.zero,
      ),
    );
  } else if (blendMode == LoveGraphicsBlendMode.screen) {
    pass.setColorBlendEquation(
      gpu.ColorBlendEquation(
        colorBlendOperation: gpu.BlendOperation.add,
        sourceColorBlendFactor: gpu.BlendFactor.one,
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

gpu.StencilOperation _stencilOperationForLove(LoveGraphicsStencilAction action) {
  return switch (action) {
    LoveGraphicsStencilAction.replace => gpu.StencilOperation.setToReferenceValue,
    LoveGraphicsStencilAction.increment => gpu.StencilOperation.incrementClamp,
    LoveGraphicsStencilAction.decrement => gpu.StencilOperation.decrementClamp,
    LoveGraphicsStencilAction.incrementWrap => gpu.StencilOperation.incrementWrap,
    LoveGraphicsStencilAction.decrementWrap => gpu.StencilOperation.decrementWrap,
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
  pass.setScissor(
    gpu.Scissor(x: x, y: y, width: width, height: height),
  );
}
