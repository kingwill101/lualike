local overrides = {
  modules = {
    ['love'] = {
      status = 'implemented',
      conformance = 'smoke-tested',
      notes = 'Owns bootstrap, callback dispatch, lifecycle shims, and global compatibility behavior. LOVE version queries, deprecation-output state helpers, love.conf bootstrap, the default love.run frame loop, love.errorhandler error-loop integration, and the shared Data/Object base-type surface are implemented.',
    },
    ['love.data'] = {
      status = 'implemented',
      conformance = 'smoke-tested',
      notes = 'Backed by pure-Dart data wrappers for ByteData, DataView, and CompressedData, plus LOVE-style encode/decode, hashing, pack/unpack, and enum tables. Compression and decompression support zlib, gzip, deflate, and LOVE-compatible LZ4 blocks with the same 4-byte uncompressed-size header used by upstream LOVE. The current Dart LZ4 encoder prioritizes block-format compatibility over matching liblz4\'s compression-ratio heuristics.',
    },
    ['love.event'] = {
      status = 'implemented',
      conformance = 'smoke-tested',
      notes = 'Backed by a runtime-managed event queue with LOVE-style poll, wait, quit, callback dispatch integration, and Event enum tables.',
    },
    ['love.audio'] = {
      status = 'implemented',
      conformance = 'smoke-tested',
      notes = 'Backed by host-managed listener, source, and recording-device state with LOVE-style Source, queueable-source, enum, and effect/filter APIs. Playback is delegated to host-provided backends; the default headless backend is silent, and effect/filter bindings currently round-trip logical state rather than applying DSP themselves.',
    },
    ['love.filesystem'] = {
      notes = 'Maps LOVE filesystem semantics onto Flutter assets plus persistent save directories.',
    },
    ['love.graphics'] = {
      notes = 'Largest rendering surface; expected to bridge onto Flame rendering and Flutter canvas primitives.',
    },
    ['love.image'] = {
      status = 'implemented',
      conformance = 'smoke-tested',
      notes = 'Backed by pure-Dart ImageData and CompressedImageData wrappers with LOVE-style decode-from-bytes/filesystem/Data inputs, pixel mutation, paste/mapPixel, encode-to-FileData, mipmap generation, and compressed texture metadata parsing for DDS, KTX, PKM, ASTC, and PVR containers. Encoded raster export currently supports PNG, JPG, BMP, and TGA.',
    },
    ['love.joystick'] = {
      status = 'implemented',
      conformance = 'smoke-tested',
      notes = 'Backed by host-managed joystick descriptors with LOVE-style querying, virtual gamepad mappings, enum tables, mapping-string persistence, filesystem round-tripping, runtime callback wrapper plus dispatch helpers, a host-side joystick input adapter for native ingestion, and Flame key-event routing for supported Flutter gamepad and DPAD device sources. Direct platform wiring remains integration-specific.',
    },
    ['love.keyboard'] = {
      status = 'implemented',
      conformance = 'smoke-tested',
      notes = 'Backed by host-managed key and scancode state with LOVE-style key/scancode mapping, pressed-state queries, key-repeat flags, screen-keyboard capability, and text-input area tracking. Flame integration also dispatches key, textinput, and textedited callbacks from Flutter input events.',
    },
    ['love.math'] = {
      status = 'implemented',
      conformance = 'smoke-tested',
      notes = 'Backed by pure-Dart color conversion, gamma helpers, deterministic random-generator state, noise, polygon helpers, and BezierCurve/Transform object wrappers, including MatrixLayout enum support.',
    },
    ['love.mouse'] = {
      status = 'implemented',
      conformance = 'smoke-tested',
      notes = 'Backed by host-managed pointer state with LOVE-style position, button, visibility, grab, relative-mode, and cursor APIs plus Cursor objects for system and image cursors. Flame integration applies supported system cursors through Flutter mouse regions and falls back gracefully where arbitrary native image cursors are unavailable.',
    },
    ['love.physics'] = {
      status = 'implemented',
      conformance = 'smoke-tested',
      notes = 'Backed by a Forge2D bridge for LOVE-style meter scaling, World/Body/Fixture/Shape/Contact/Joint object wrappers, circle/polygon/edge/chain constructors, all documented LOVE 11.5 joint constructors plus object surfaces, distance queries, transform and state mutation, fixture filter helpers, fixture and shape ray casts, world query and ray-cast callbacks, contact-count and body-touching queries, body inertia mutation, fixture bounds and mass-data queries, contact enumeration and manifold queries, fixture shape cloning, rebuild-on-shape-mutation behavior, and destroyed-object error semantics. Contact friction and restitution setters are replayed into Forge2D through temporary fixture-material reset shims so overrides affect later solver steps even though Forge2D does not expose public direct setters for the underlying contact core, and the LOVE source\'s tangent-speed contact accessors are bridged directly onto Forge2D\'s native tangent-speed field. World collision callbacks and contact-filter callbacks now dispatch synchronously during the Forge2D step in the AST runtime path used by the LOVE bindings, so world:isLocked() matches callback timing and preSolve contact mutations can affect the current solver pass. Like upstream Box2D-style stepping, continuous-collision processing can still surface multiple shouldCollide, preSolve, and postSolve evaluations for the same fixture pair or contact within a single World:update.',
    },
    ['love.sound'] = {
      status = 'implemented',
      conformance = 'smoke-tested',
      notes = 'Backed by pure-Dart SoundData and Decoder wrappers with LOVE-style sample access, cloning, chunked decode, decoder-drain construction, WAV encoding, and filesystem/Data overloads. Pure-Dart decoder coverage targets WAV containers, including PCM and IEEE float variants normalized into LOVE-compatible sample data, and recognized Ogg, MP3, and FLAC payloads now additionally decode through a host `ffmpeg` fallback on IO platforms when available.',
    },
    ['love.system'] = {
      status = 'implemented',
      conformance = 'smoke-tested',
      notes = 'Backed by host-managed platform service state for clipboard, URL launching, power info, vibration, and processor metadata, including LOVE enum tables for power-state constants.',
    },
    ['love.thread'] = {
      status = 'implemented',
      conformance = 'smoke-tested',
      notes = 'Backed by shared async worker runtimes with LOVE-style Channel and Thread objects, named-channel registry, code-string and filesystem-backed thread loading, threaderror event dispatch, and message marshalling for booleans, numbers, strings, Channel, Thread, and table payloads compatible with the implemented runtime. Worker runtimes currently execute asynchronously within the same Dart isolate while sharing the parent host, event queue bridge, and filesystem adapter state.',
    },
    ['love.timer'] = {
      status = 'implemented',
      conformance = 'smoke-tested',
      notes = 'Backed by the host clock for LOVE-style time, delta, FPS, average delta, frame stepping, and sleep semantics.',
    },
    ['love.touch'] = {
      status = 'implemented',
      conformance = 'smoke-tested',
      notes = 'Backed by host-managed active touch state with LOVE-style touch id ordering, position and pressure queries, and adapter-driven touch callback dispatch.',
    },
    ['love.video'] = {
      status = 'shimmed',
      conformance = 'smoke-tested',
      notes = 'Backed by a control-layer VideoStream wrapper with filename/File construction, playback-state timing, seek/rewind/tell semantics, and sync sharing with Source objects or other streams. Graphics-side Video wrappers now expose constructor, filter, Source-sync APIs, sampled frame extraction, and live playback control through Flutter-backed media_kit integration. The renderer targets Flutter-compatible video playback rather than upstream LOVE\'s YCbCr shader path, and now prefers a persistent native video texture overlay for supported draw states including standard alpha, premultiplied alpha, and opaque replace/none blending plus quad/scissor/tint transforms while falling back to sampled frame images for unsupported states such as shader-bound or destination-aware blend/write-mask cases.',
    },
    ['love.window'] = {
      status = 'implemented',
      conformance = 'smoke-tested',
      notes = 'Backed by host-managed window metrics, display descriptors, and message-box callbacks, including LOVE enum tables for display orientation, fullscreen type, and message-box type constants.',
    },
  },
  extra_symbols = {},
  symbols = {
    ['love.run'] = {
      phase = 'foundation',
      notes = 'Default LOVE main-loop closure, including load bootstrap, event pump and quit semantics, timer stepping, per-frame origin reset before draw, and sleep pacing.',
    },
    ['love.load'] = {
      phase = 'foundation',
      notes = 'Startup hook for user code after runtime bootstrap and before steady-state frames.',
    },
    ['love.update'] = {
      phase = 'foundation',
      notes = 'Maps LOVE update timing onto Flame update ticks.',
    },
    ['love.draw'] = {
      phase = 'foundation',
      notes = 'Maps LOVE draw callback onto Flame plus Flutter render flow.',
    },
    ['love.conf'] = {
      phase = 'foundation',
      notes = 'Configuration bootstrap is applied before main.lua runs, including identity, audio, window, and module toggle state.',
    },
    ['love.graphics.newCanvas'] = {
      phase = 'high',
      notes = 'Requires an offscreen rendering strategy compatible with Flutter and Flame.',
    },
    ['love.graphics.newShader'] = {
      phase = 'high',
      notes = 'Will likely require a substantial shader compatibility shim instead of direct 1:1 execution.',
    },
    ['love.physics.newWorld'] = {
      phase = 'high',
      notes = 'Root Forge2D bridge constructor for LOVE physics compatibility.',
    },
    ['love.audio.newSource'] = {
      phase = 'high',
      notes = 'Primary audio object constructor and likely the anchor for the audio bridge surface.',
    },
  },
}

local function merge_fields(target, fields)
  for key, value in pairs(fields) do
    target[key] = value
  end
end

local function apply_symbol_overrides(symbols, fields)
  for _, symbol in ipairs(symbols) do
    local entry = overrides.symbols[symbol] or {}
    merge_fields(entry, fields)
    overrides.symbols[symbol] = entry
  end
end

local function add_extra_symbol(module_name, symbol, kind, container, fields)
  overrides.extra_symbols[#overrides.extra_symbols + 1] = {
    module = module_name,
    symbol = symbol,
    kind = kind,
    container = container,
  }

  if fields ~= nil then
    local entry = overrides.symbols[symbol] or {}
    merge_fields(entry, fields)
    overrides.symbols[symbol] = entry
  end
end

merge_fields(overrides.modules['love.filesystem'], {
  status = 'partial',
  conformance = 'smoke-tested',
  notes = 'Maps LOVE filesystem semantics onto Flutter assets plus persistent save directories. Directory mounts, save identity writes, File/FileData wrappers, LOVE enum tables for file, buffer, decoder, and node-type constants, source-parity File:getExtension support, host-provided DroppedFile wrappers, Lua package loading, and zip, tar-family, grp/qpak, hog, mvl, slb, vdf, wad, iso, and 7z archive mounts from direct filesystem paths, logical source/save-relative paths, DroppedFile, FileData, and generic Data wrappers are implemented. 7z archives whose file data and encoded headers, when present, use single-folder Copy, LZMA, or LZMA2 coder chains are decoded in pure Dart across platforms. More advanced 7z layouts such as multi-coder or multi-pack-stream folders still fall back to a host `7z`/`7za`/`7zr` tool on IO platforms and remain unsupported elsewhere, so full cross-platform parity remains partial.',
})

overrides.modules['love.font'] = overrides.modules['love.font'] or {}
merge_fields(overrides.modules['love.font'], {
  notes = 'Backed by pure-Dart Rasterizer and GlyphData wrappers plus host-assisted TrueType loading, image-font strip parsing, BMFont definition parsing, LOVE hinting enum tables, graphics-font interop, and LOVE-style validation/error text. TrueType rasterizers created without source or injected default font bytes still answer glyph queries with estimated metrics, but glyph-count enumeration remains unavailable until real font data is present.',
})

apply_symbol_overrides({
  'love.font',
  'love.font.newBMFontRasterizer',
  'love.font.newGlyphData',
  'love.font.newImageRasterizer',
  'love.font.newRasterizer',
  'love.font.newTrueTypeRasterizer',
  'GlyphData',
  'GlyphData:getAdvance',
  'GlyphData:getBearing',
  'GlyphData:getBoundingBox',
  'GlyphData:getDimensions',
  'GlyphData:getFormat',
  'GlyphData:getGlyph',
  'GlyphData:getGlyphString',
  'GlyphData:getHeight',
  'GlyphData:getWidth',
  'Rasterizer',
  'Rasterizer:getAdvance',
  'Rasterizer:getAscent',
  'Rasterizer:getDescent',
  'Rasterizer:getGlyphCount',
  'Rasterizer:getGlyphData',
  'Rasterizer:getHeight',
  'Rasterizer:getLineHeight',
  'Rasterizer:hasGlyphs',
  'HintingMode',
  'HintingMode.normal',
  'HintingMode.light',
  'HintingMode.mono',
  'HintingMode.none',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

overrides.symbols['love.font.newRasterizer'] = overrides.symbols['love.font.newRasterizer'] or {}
merge_fields(overrides.symbols['love.font.newRasterizer'], {
  notes = 'Dispatches to LOVE-style TrueType or BMFont rasterizer construction based on numeric versus filesystem or FileData inputs, including BMFont auto-detection from mounted file sources and FileData payloads.',
})

overrides.symbols['Rasterizer:getGlyphCount'] = overrides.symbols['Rasterizer:getGlyphCount'] or {}
merge_fields(overrides.symbols['Rasterizer:getGlyphCount'], {
  notes = 'Implemented for image and BMFont rasterizers and for TrueType rasterizers when source or injected default font bytes provide glyph-table metadata. Source-less TrueType rasterizers still throw a compatibility error here while individual glyph queries return estimated metrics.',
})

merge_fields(overrides.modules['love.graphics'], {
  notes = 'Partial compatibility surface with tested environment and advanced-state queries, transform stack, primitive draw commands, image/canvas/quad/texture objects, font and text objects, mesh, shader, particle-system, sprite-batch, deferred screenshot capture, array-image construction plus drawLayer rendering, layered array-canvas render targets, manual layered mipmap-table construction, control-layer cube and volume image constructors, packed cubemap and volume layout extraction, layered CompressedImageData constructor parity, DXT1/DXT3/DXT5/ETC1/ETC2rgb/ETC2rgba1/ETC2rgba/EACr/EACrs/EACrg/EACrgs/BC4/BC4s/BC5/BC5s compressed-image software rasterization for screenshot and canvas-readback paths, software-backed stencil replay for canvas readback, screenshot capture, and live Flame presentation, control-layer Video wrappers, basic canvas-backed rendering, and Lua-facing graphics enum tables. Registered Flutter fragment-asset shaders are supported on the live Flame renderer, but Canvas:newImageData and captureScreenshot now raise explicit unsupported errors for those surfaces because the software rasterizer cannot reproduce arbitrary fragment programs. Remaining gaps are shader-only volume/cubemap draw paths, broader compressed-texture rasterization outside DXT1/DXT3/DXT5/ETC1/ETC2rgb/ETC2rgba1/ETC2rgba/EACr/EACrs/EACrg/EACrgs/BC4/BC4s/BC5/BC5s in the software renderer, and exact glyph fidelity when stencil-active surfaces fall back to the software rasterizer. Video objects now prefer a Flutter-compatible persistent media_kit texture path for supported draw states including plain, quad-cropped, scissored, tinted, standard alpha, premultiplied alpha, and opaque replace/none rendering, while unsupported states still fall back to sampled frame images instead of the upstream LOVE shader-based video path.',
})

apply_symbol_overrides({
  'love.graphics',
}, {
  status = 'partial',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'love.graphics.applyTransform',
  'love.graphics.arc',
  'love.graphics.circle',
  'love.graphics.clear',
  'love.graphics.captureScreenshot',
  'love.graphics.draw',
  'love.graphics.ellipse',
  'love.graphics.getBackgroundColor',
  'love.graphics.getBlendMode',
  'love.graphics.getCanvas',
  'love.graphics.getCanvasFormats',
  'love.graphics.getColor',
  'love.graphics.getColorMask',
  'love.graphics.getDPIScale',
  'love.graphics.getDefaultFilter',
  'love.graphics.getDepthMode',
  'love.graphics.getDimensions',
  'love.graphics.getFont',
  'love.graphics.getFrontFaceWinding',
  'love.graphics.getHeight',
  'love.graphics.getImageFormats',
  'love.graphics.getLineJoin',
  'love.graphics.getLineStyle',
  'love.graphics.getLineWidth',
  'love.graphics.getMeshCullMode',
  'love.graphics.getPixelDimensions',
  'love.graphics.getPixelHeight',
  'love.graphics.getPixelWidth',
  'love.graphics.getPointSize',
  'love.graphics.getRendererInfo',
  'love.graphics.getScissor',
  'love.graphics.getShader',
  'love.graphics.getStackDepth',
  'love.graphics.getStats',
  'love.graphics.getStencilTest',
  'love.graphics.getSupported',
  'love.graphics.getSystemLimits',
  'love.graphics.getTextureTypes',
  'love.graphics.getWidth',
  'love.graphics.intersectScissor',
  'love.graphics.inverseTransformPoint',
  'love.graphics.isWireframe',
  'love.graphics.line',
  'love.graphics.newCanvas',
  'love.graphics.newFont',
  'love.graphics.newImage',
  'love.graphics.newImageFont',
  'love.graphics.newMesh',
  'love.graphics.newParticleSystem',
  'love.graphics.newQuad',
  'love.graphics.newShader',
  'love.graphics.newSpriteBatch',
  'love.graphics.newText',
  'love.graphics.origin',
  'love.graphics.points',
  'love.graphics.polygon',
  'love.graphics.pop',
  'love.graphics.print',
  'love.graphics.printf',
  'love.graphics.push',
  'love.graphics.rectangle',
  'love.graphics.replaceTransform',
  'love.graphics.reset',
  'love.graphics.rotate',
  'love.graphics.scale',
  'love.graphics.setBackgroundColor',
  'love.graphics.setBlendMode',
  'love.graphics.setCanvas',
  'love.graphics.setColor',
  'love.graphics.setColorMask',
  'love.graphics.setDefaultFilter',
  'love.graphics.setDepthMode',
  'love.graphics.setFont',
  'love.graphics.setFrontFaceWinding',
  'love.graphics.setLineJoin',
  'love.graphics.setLineStyle',
  'love.graphics.setLineWidth',
  'love.graphics.setMeshCullMode',
  'love.graphics.setNewFont',
  'love.graphics.setPointSize',
  'love.graphics.setScissor',
  'love.graphics.setShader',
  'love.graphics.setStencilTest',
  'love.graphics.setWireframe',
  'love.graphics.shear',
  'love.graphics.transformPoint',
  'love.graphics.translate',
  'Canvas',
  'Canvas:generateMipmaps',
  'Canvas:getMSAA',
  'Canvas:getMipmapMode',
  'Canvas:newImageData',
  'Canvas:renderTo',
  'Font',
  'Font:getAscent',
  'Font:getBaseline',
  'Font:getDPIScale',
  'Font:getDescent',
  'Font:getFilter',
  'Font:getHeight',
  'Font:getKerning',
  'Font:getLineHeight',
  'Font:getWidth',
  'Font:getWrap',
  'Font:hasGlyphs',
  'Font:setFallbacks',
  'Font:setFilter',
  'Font:setLineHeight',
  'Image',
  'Image:isCompressed',
  'Image:isFormatLinear',
  'Image:replacePixels',
  'Mesh',
  'Mesh:attachAttribute',
  'Mesh:detachAttribute',
  'Mesh:flush',
  'Mesh:getDrawMode',
  'Mesh:getDrawRange',
  'Mesh:getTexture',
  'Mesh:getVertex',
  'Mesh:getVertexAttribute',
  'Mesh:getVertexCount',
  'Mesh:getVertexFormat',
  'Mesh:getVertexMap',
  'Mesh:isAttributeEnabled',
  'Mesh:setAttributeEnabled',
  'Mesh:setDrawMode',
  'Mesh:setDrawRange',
  'Mesh:setTexture',
  'Mesh:setVertex',
  'Mesh:setVertexAttribute',
  'Mesh:setVertexMap',
  'Mesh:setVertices',
  'ParticleSystem',
  'ParticleSystem:clone',
  'ParticleSystem:emit',
  'ParticleSystem:getBufferSize',
  'ParticleSystem:getColors',
  'ParticleSystem:getCount',
  'ParticleSystem:getDirection',
  'ParticleSystem:getEmissionArea',
  'ParticleSystem:getEmissionRate',
  'ParticleSystem:getEmitterLifetime',
  'ParticleSystem:getInsertMode',
  'ParticleSystem:getLinearAcceleration',
  'ParticleSystem:getLinearDamping',
  'ParticleSystem:getOffset',
  'ParticleSystem:getParticleLifetime',
  'ParticleSystem:getPosition',
  'ParticleSystem:getQuads',
  'ParticleSystem:getRadialAcceleration',
  'ParticleSystem:getRotation',
  'ParticleSystem:getSizeVariation',
  'ParticleSystem:getSizes',
  'ParticleSystem:getSpeed',
  'ParticleSystem:getSpin',
  'ParticleSystem:getSpinVariation',
  'ParticleSystem:getSpread',
  'ParticleSystem:getTangentialAcceleration',
  'ParticleSystem:getTexture',
  'ParticleSystem:hasRelativeRotation',
  'ParticleSystem:isActive',
  'ParticleSystem:isPaused',
  'ParticleSystem:isStopped',
  'ParticleSystem:moveTo',
  'ParticleSystem:pause',
  'ParticleSystem:reset',
  'ParticleSystem:setBufferSize',
  'ParticleSystem:setColors',
  'ParticleSystem:setDirection',
  'ParticleSystem:setEmissionArea',
  'ParticleSystem:setEmissionRate',
  'ParticleSystem:setEmitterLifetime',
  'ParticleSystem:setInsertMode',
  'ParticleSystem:setLinearAcceleration',
  'ParticleSystem:setLinearDamping',
  'ParticleSystem:setOffset',
  'ParticleSystem:setParticleLifetime',
  'ParticleSystem:setPosition',
  'ParticleSystem:setQuads',
  'ParticleSystem:setRadialAcceleration',
  'ParticleSystem:setRelativeRotation',
  'ParticleSystem:setRotation',
  'ParticleSystem:setSizeVariation',
  'ParticleSystem:setSizes',
  'ParticleSystem:setSpeed',
  'ParticleSystem:setSpin',
  'ParticleSystem:setSpinVariation',
  'ParticleSystem:setSpread',
  'ParticleSystem:setTangentialAcceleration',
  'ParticleSystem:setTexture',
  'ParticleSystem:start',
  'ParticleSystem:stop',
  'ParticleSystem:update',
  'Quad',
  'Quad:getTextureDimensions',
  'Quad:getViewport',
  'Quad:setViewport',
  'Shader',
  'Shader:getWarnings',
  'Shader:hasUniform',
  'Shader:send',
  'Shader:sendColor',
  'SpriteBatch',
  'SpriteBatch:add',
  'SpriteBatch:addLayer',
  'SpriteBatch:attachAttribute',
  'SpriteBatch:clear',
  'SpriteBatch:flush',
  'SpriteBatch:getBufferSize',
  'SpriteBatch:getColor',
  'SpriteBatch:getCount',
  'SpriteBatch:getDrawRange',
  'SpriteBatch:getTexture',
  'SpriteBatch:set',
  'SpriteBatch:setColor',
  'SpriteBatch:setDrawRange',
  'SpriteBatch:setLayer',
  'SpriteBatch:setTexture',
  'Text',
  'Text:add',
  'Text:addf',
  'Text:clear',
  'Text:getDimensions',
  'Text:getFont',
  'Text:getHeight',
  'Text:getWidth',
  'Text:set',
  'Text:setFont',
  'Text:setf',
  'Texture',
  'Texture:getDPIScale',
  'Texture:getDepth',
  'Texture:getDepthSampleMode',
  'Texture:getDimensions',
  'Texture:getFilter',
  'Texture:getFormat',
  'Texture:getHeight',
  'Texture:getLayerCount',
  'Texture:getMipmapCount',
  'Texture:getMipmapFilter',
  'Texture:getPixelDimensions',
  'Texture:getPixelHeight',
  'Texture:getPixelWidth',
  'Texture:getTextureType',
  'Texture:getWidth',
  'Texture:getWrap',
  'Texture:isReadable',
  'Texture:setDepthSampleMode',
  'Texture:setFilter',
  'Texture:setMipmapFilter',
  'Texture:setWrap',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'love.graphics.drawLayer',
  'love.graphics.newArrayImage',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'love.graphics.newCubeImage',
  'love.graphics.newVolumeImage',
}, {
  status = 'partial',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'love.graphics.stencil',
}, {
  status = 'partial',
  conformance = 'smoke-tested',
})

overrides.symbols['love.graphics.newMesh'] = overrides.symbols['love.graphics.newMesh'] or {}
merge_fields(overrides.symbols['love.graphics.newMesh'], {
  notes = 'Supports LOVE-style vertex-table and vertex-count overloads with draw-mode and usage hints, then exposes draw-range, vertex-map, texture, and per-attribute mesh wrappers.',
})

overrides.symbols['love.graphics.drawLayer'] = overrides.symbols['love.graphics.drawLayer'] or {}
merge_fields(overrides.symbols['love.graphics.drawLayer'], {
  notes = 'Draws selected layers from array textures and array canvases using the normal image-command path, including layered Canvas snapshots produced by setCanvas and Canvas:renderTo on non-2D array targets. Volume and cube textures remain explicit unsupported draw targets.',
})

overrides.symbols['love.graphics.getCanvas'] = overrides.symbols['love.graphics.getCanvas'] or {}
merge_fields(overrides.symbols['love.graphics.getCanvas'], {
  notes = 'Returns the active 2D Canvas directly, and returns LOVE-style render-target tables for non-2D Canvas layers or faces so array, volume, and cubemap targets report layer or face together with mipmap. Multi-target and depth-stencil metadata remain partial because the current runtime only drives the first color target.',
})

overrides.symbols['love.graphics.newImage'] = overrides.symbols['love.graphics.newImage'] or {}
merge_fields(overrides.symbols['love.graphics.newImage'], {
  notes = 'Constructs Images from filename, FileData, File, ImageData, or CompressedImageData sources with LOVE-style filter, wrap, mipmap, and dpiscale settings. DXT1/DXT3/DXT5/ETC1/ETC2rgb/ETC2rgba1/ETC2rgba/EACr/EACrs/EACrg/EACrgs/BC4/BC4s/BC5/BC5s-backed compressed images now participate in the software screenshot and canvas-readback rasterizer path, while broader compressed-format rasterization remains partial.',
})

overrides.symbols['love.graphics.newArrayImage'] = overrides.symbols['love.graphics.newArrayImage'] or {}
merge_fields(overrides.symbols['love.graphics.newArrayImage'], {
  notes = 'Builds array textures from sequential tables of filename, FileData, File, ImageData, or CompressedImageData slice sources, including manual per-slice mipmap tables, validates matching dimensions and mip counts, and stores per-slice images for drawLayer, SpriteBatch layer rendering, and slice-aware replacePixels. DXT1/DXT3/DXT5/ETC1/ETC2rgb/ETC2rgba1/ETC2rgba/EACr/EACrs/EACrg/EACrgs/BC4/BC4s/BC5/BC5s-backed compressed slices now rasterize through the software screenshot and canvas-readback path, while broader compressed-format support remains partial.',
})

overrides.symbols['love.graphics.newCubeImage'] = overrides.symbols['love.graphics.newCubeImage'] or {}
merge_fields(overrides.symbols['love.graphics.newCubeImage'], {
  notes = 'Partially implemented for packed single-source cubemap layouts, flat tables of packed cubemap mipmap sources, and tables of exactly 6 face images with matching square dimensions, including per-face manual mipmap tables and CompressedImageData face sources. Direct cube-texture drawing remains unsupported in the current runtime.',
})

overrides.symbols['love.graphics.newVolumeImage'] = overrides.symbols['love.graphics.newVolumeImage'] or {}
merge_fields(overrides.symbols['love.graphics.newVolumeImage'], {
  notes = 'Partially implemented for packed single-source layer strips and for sequential tables of 2D layer images with matching dimensions and metadata, including manual mipmap layouts where the outer table is mipmap levels and each inner table contains all layers for that mipmap, plus CompressedImageData layer sources. Volume textures are created as shader-oriented metadata containers and still raise an explicit unsupported error when drawn.',
})

overrides.symbols['love.graphics.setCanvas'] = overrides.symbols['love.graphics.setCanvas'] or {}
merge_fields(overrides.symbols['love.graphics.setCanvas'], {
  notes = 'Supports regular 2D Canvas targets together with LOVE-style non-2D target selection via (canvas, slice [, mipmap]) and table-of-tables render-target entries using layer or face keys. The current runtime routes drawing to the selected layered Canvas surface and restores it through Canvas:renderTo, but multi-target rendering still only uses the first color target and mipmap render targets other than level 1 remain unsupported.',
})

overrides.symbols['love.graphics.stencil'] = overrides.symbols['love.graphics.stencil'] or {}
merge_fields(overrides.symbols['love.graphics.stencil'], {
  notes = 'Records stencil clear and write commands and replays them through the software canvas rasterizer, so Canvas:newImageData, captureScreenshot, and live Flame presentation respect replace and increment-style stencil workflows together with setStencilTest. Stencil-active surfaces currently inherit the software rasterizer\'s approximate text and glyph rendering instead of the normal Flutter text path.',
})

overrides.symbols['Canvas:newImageData'] = overrides.symbols['Canvas:newImageData'] or {}
merge_fields(overrides.symbols['Canvas:newImageData'], {
  notes = 'Reads back readable Canvas contents into ImageData, including explicit layer or face selection for non-2D Canvas targets before optional mipmap and rectangle arguments. Non-2D canvases require an explicit slice argument and readback still rasterizes from the base render target surface because direct mipmap render targets are not implemented. Surfaces that depend on registered Flutter fragment-asset shaders now fail with an explicit unsupported error because the software rasterizer cannot reproduce arbitrary fragment programs.',
})

overrides.symbols['Image:replacePixels'] = overrides.symbols['Image:replacePixels'] or {}
merge_fields(overrides.symbols['Image:replacePixels'], {
  notes = 'Replaces readable ImageData-backed pixel regions on 2D and layered textures, including array, volume, and cube slices. Non-2D textures require an explicit slice argument, while the 2D binding mirrors upstream LOVE by ignoring the slice argument slot and using the following arguments for mipmap and destination coordinates.',
})

overrides.symbols['Canvas:renderTo'] = overrides.symbols['Canvas:renderTo'] or {}
merge_fields(overrides.symbols['Canvas:renderTo'], {
  notes = 'Wraps setCanvas for Canvas-local rendering and now accepts explicit slice arguments on non-2D Canvas targets so layered Canvas surfaces can be rendered independently and then restored to the previous render target. Direct mipmap render targets remain unsupported.',
})

overrides.symbols['love.graphics.newShader'] = overrides.symbols['love.graphics.newShader'] or {}
merge_fields(overrides.symbols['love.graphics.newShader'], {
  status = 'partial',
  conformance = 'smoke-tested',
  notes = 'Accepts literal source strings, LOVE filesystem paths, FileData, and File wrappers, runs them through the same LOVE-style stage scan used by `_shaderCodeToGLSL`, and preserves missing `position`/`effect` parse errors plus shader-language mismatch errors before backend rejection. Mounted Flutter runtime-effect files loaded through the LOVE filesystem can infer registered fragment-asset keys relative to the mounted source root, and Flutter hosts now eagerly validate those registered assets so missing shader bundle entries fail at construction time instead of first draw. The Flutter backend currently executes the compatibility-emulated radial gradient and desaturation-tint shader subsets plus registered Flutter fragment-asset shaders, while other runtime shader source still fails with an explicit unsupported-backend error instead of attempting to execute upstream-style GLSL.',
})

overrides.symbols['love.graphics.getShader'] = overrides.symbols['love.graphics.getShader'] or {}
merge_fields(overrides.symbols['love.graphics.getShader'], {
  notes = 'Returns the currently active shader wrapper or nil when no shader is bound, and mutating the returned wrapper updates the active shader state for subsequent draws.',
})

apply_symbol_overrides({
  'AlignMode',
  'AlignMode.center',
  'AlignMode.left',
  'AlignMode.right',
  'AlignMode.justify',
  'ArcType',
  'ArcType.pie',
  'ArcType.open',
  'ArcType.closed',
  'AreaSpreadDistribution',
  'AreaSpreadDistribution.uniform',
  'AreaSpreadDistribution.normal',
  'AreaSpreadDistribution.ellipse',
  'AreaSpreadDistribution.borderellipse',
  'AreaSpreadDistribution.borderrectangle',
  'AreaSpreadDistribution.none',
  'BlendAlphaMode',
  'BlendAlphaMode.alphamultiply',
  'BlendAlphaMode.premultiplied',
  'BlendMode',
  'BlendMode.alpha',
  'BlendMode.replace',
  'BlendMode.screen',
  'BlendMode.add',
  'BlendMode.subtract',
  'BlendMode.multiply',
  'BlendMode.lighten',
  'BlendMode.darken',
  'BlendMode.additive',
  'BlendMode.subtractive',
  'BlendMode.multiplicative',
  'BlendMode.premultiplied',
  'CompareMode',
  'CompareMode.equal',
  'CompareMode.notequal',
  'CompareMode.less',
  'CompareMode.lequal',
  'CompareMode.gequal',
  'CompareMode.greater',
  'CompareMode.never',
  'CompareMode.always',
  'CullMode',
  'CullMode.back',
  'CullMode.front',
  'CullMode.none',
  'DrawMode',
  'DrawMode.fill',
  'DrawMode.line',
  'FilterMode',
  'FilterMode.linear',
  'FilterMode.nearest',
  'GraphicsFeature',
  'GraphicsFeature.clampzero',
  'GraphicsFeature.lighten',
  'GraphicsFeature.multicanvasformats',
  'GraphicsFeature.glsl3',
  'GraphicsFeature.instancing',
  'GraphicsFeature.fullnpot',
  'GraphicsFeature.pixelshaderhighp',
  'GraphicsFeature.shaderderivatives',
  'GraphicsLimit',
  'GraphicsLimit.pointsize',
  'GraphicsLimit.texturesize',
  'GraphicsLimit.multicanvas',
  'GraphicsLimit.canvasmsaa',
  'GraphicsLimit.texturelayers',
  'GraphicsLimit.volumetexturesize',
  'GraphicsLimit.cubetexturesize',
  'GraphicsLimit.anisotropy',
  'IndexDataType',
  'IndexDataType.uint16',
  'IndexDataType.uint32',
  'LineJoin',
  'LineJoin.miter',
  'LineJoin.none',
  'LineJoin.bevel',
  'LineStyle',
  'LineStyle.rough',
  'LineStyle.smooth',
  'MeshDrawMode',
  'MeshDrawMode.fan',
  'MeshDrawMode.strip',
  'MeshDrawMode.triangles',
  'MeshDrawMode.points',
  'MipmapMode',
  'MipmapMode.none',
  'MipmapMode.auto',
  'MipmapMode.manual',
  'ParticleInsertMode',
  'ParticleInsertMode.top',
  'ParticleInsertMode.bottom',
  'ParticleInsertMode.random',
  'SpriteBatchUsage',
  'SpriteBatchUsage.dynamic',
  'SpriteBatchUsage.static',
  'SpriteBatchUsage.stream',
  'StackType',
  'StackType.transform',
  'StackType.all',
  'StencilAction',
  'StencilAction.replace',
  'StencilAction.increment',
  'StencilAction.decrement',
  'StencilAction.incrementwrap',
  'StencilAction.decrementwrap',
  'StencilAction.invert',
  'TextureType',
  'TextureType.2d',
  'TextureType.array',
  'TextureType.cube',
  'TextureType.volume',
  'VertexAttributeStep',
  'VertexAttributeStep.pervertex',
  'VertexAttributeStep.perinstance',
  'VertexWinding',
  'VertexWinding.cw',
  'VertexWinding.ccw',
  'WrapMode',
  'WrapMode.clamp',
  'WrapMode.repeat',
  'WrapMode.mirroredrepeat',
  'WrapMode.clampzero',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

overrides.symbols['Mesh:attachAttribute'] = overrides.symbols['Mesh:attachAttribute'] or {}
merge_fields(overrides.symbols['Mesh:attachAttribute'], {
  notes = 'Currently records the named attribute as enabled for compatibility; full multi-mesh attribute-stream composition is not yet modeled.',
})

overrides.symbols['Shader:getWarnings'] = overrides.symbols['Shader:getWarnings'] or {}
merge_fields(overrides.symbols['Shader:getWarnings'], {
  notes = 'Always returns an empty string because the runtime has no GLSL compiler or warning pipeline, while preserving the upstream string return type.',
})

overrides.symbols['Shader:hasUniform'] = overrides.symbols['Shader:hasUniform'] or {}
merge_fields(overrides.symbols['Shader:hasUniform'], {
  notes = 'Checks parsed shader-uniform declarations plus a heuristic source scan for declared `extern` or `uniform` names, and also reports true for uniforms that have already been sent through the compatibility wrapper.',
})

overrides.symbols['Shader:send'] = overrides.symbols['Shader:send'] or {}
merge_fields(overrides.symbols['Shader:send'], {
  notes = 'Stores sent uniform values on the compatibility shader wrapper and snapshots them into subsequent draw commands. Calls require at least one payload value, the named uniform must exist in the parsed shader source, parsed float, integer, unsigned integer, boolean, vector, and square matrix uniforms validate payload shapes before storage, square matrix uniforms accept LOVE-style `row` and `column` layout strings with canonical column-major storage for the supported compatibility subset, sampler uniforms currently accept Image or Canvas uploads only for registered Flutter fragment-asset shaders and otherwise fail with an explicit unsupported-backend error, and LOVE `Data` upload overloads currently fail with an explicit unsupported-backend error instead of silently storing opaque objects.',
})

overrides.symbols['Shader:sendColor'] = overrides.symbols['Shader:sendColor'] or {}
merge_fields(overrides.symbols['Shader:sendColor'], {
  notes = 'Stores sent color uniform values on the compatibility shader wrapper and snapshots them into subsequent draw commands. The named uniform must exist, non-vec3 and non-vec4 uniforms are rejected, vec3 and vec4 payloads are shape-validated before storage, numeric color components are clamped into the 0 to 1 range, the current non-gamma-correct backend stores those clamped values without additional conversion, and LOVE `Data` upload overloads currently fail with an explicit unsupported-backend error.',
})

overrides.symbols['SpriteBatch:addLayer'] = overrides.symbols['SpriteBatch:addLayer'] or {}
merge_fields(overrides.symbols['SpriteBatch:addLayer'], {
  notes = 'Stores LOVE-style layer indices as per-sprite metadata in draw snapshots. Current Flame and software rendering paths resolve layered texture slices from those stored indices when drawing sprite batches.',
})

overrides.symbols['SpriteBatch:setLayer'] = overrides.symbols['SpriteBatch:setLayer'] or {}
merge_fields(overrides.symbols['SpriteBatch:setLayer'], {
  notes = 'Updates the stored per-sprite layer metadata and transform in queued draw snapshots, and current Flame and software rendering paths honor the updated layered-texture slice during sprite-batch draws.',
})

overrides.symbols['SpriteBatch:attachAttribute'] = overrides.symbols['SpriteBatch:attachAttribute'] or {}
merge_fields(overrides.symbols['SpriteBatch:attachAttribute'], {
  notes = 'Attached attribute meshes are stored and now snapshot into queued draw commands for compatibility, but the current renderer does not yet consume them during rasterization.',
})

overrides.symbols['SpriteBatch:flush'] = overrides.symbols['SpriteBatch:flush'] or {}
merge_fields(overrides.symbols['SpriteBatch:flush'], {
  notes = 'Compatibility no-op because the command-based runtime has no explicit GPU upload step for sprite batches.',
})

apply_symbol_overrides({
  'love.graphics.discard',
  'love.graphics.flushBatch',
  'love.graphics.isActive',
  'love.graphics.isGammaCorrect',
  'love.graphics.present',
  'love.graphics.validateShader',
}, {
  status = 'shimmed',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'Drawable',
  'love.graphics.drawInstanced',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'love.graphics.newVideo',
  'Video',
}, {
  status = 'shimmed',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'Video:getDimensions',
  'Video:getFilter',
  'Video:getHeight',
  'Video:getSource',
  'Video:getStream',
  'Video:getWidth',
  'Video:isPlaying',
  'Video:pause',
  'Video:play',
  'Video:rewind',
  'Video:seek',
  'Video:setFilter',
  'Video:setSource',
  'Video:tell',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

overrides.symbols['love.graphics.discard'] = overrides.symbols['love.graphics.discard'] or {}
merge_fields(overrides.symbols['love.graphics.discard'], {
  notes = 'Compatibility no-op shim for the GPU discard hint.',
})

overrides.symbols['love.graphics.drawInstanced'] = overrides.symbols['love.graphics.drawInstanced'] or {}
merge_fields(overrides.symbols['love.graphics.drawInstanced'], {
  notes = 'Uses a compatibility fallback that stores a single mesh draw command with an instance count and replays it during rasterization, so drawcall stats stay LOVE-like even though custom per-instance attached attributes are not yet consumed by the renderer.',
})

overrides.symbols['love.graphics.draw'] = overrides.symbols['love.graphics.draw'] or {}
merge_fields(overrides.symbols['love.graphics.draw'], {
  notes = 'Draws Image, Canvas, Mesh, Text, SpriteBatch, and ParticleSystem wrappers. Array textures and array canvases follow upstream LOVE\'s Quad-layer behavior, so direct draws use the Quad\'s configured layer (defaulting to the first slice) and drawLayer continues to provide the explicit layer override path. Video wrappers now prefer the Flutter-compatible persistent media_kit texture path for supported draw states including plain, quad-cropped, scissored, tinted, standard alpha, premultiplied alpha, and opaque replace/none rendering. Shader-bound or otherwise destination-aware states still fall back to sampled frame images instead of upstream LOVE\'s shader-driven YCbCr path.',
})

overrides.symbols['Drawable'] = overrides.symbols['Drawable'] or {}
merge_fields(overrides.symbols['Drawable'], {
  notes = 'Abstract compatibility marker type. Implemented drawable wrappers such as Image, Canvas, Mesh, ParticleSystem, SpriteBatch, Text, and Video already report Drawable through Object:typeOf.',
})

overrides.symbols['love.graphics.newVideo'] = overrides.symbols['love.graphics.newVideo'] or {}
merge_fields(overrides.symbols['love.graphics.newVideo'], {
  notes = 'Constructs a compatibility Video wrapper from LOVE-style filename/File or VideoStream inputs. Constructors now reject non-Theora payloads up front, filename/File inputs that cannot be opened report the upstream wrapper error `File is not open and cannot be opened`, dimensions come from parsing the Ogg Theora identification header, and the second argument mirrors the upstream Lua wrapper: it must be nil or a settings table. `settings.audio = false` detaches the stream back to independent timing, literal `settings.audio = true` raises `Video had no audio track` when no audio track is present and `love.audio was not loaded` when the audio module is absent, and other truthy values only attempt audio without forcing failure, matching the vendored wrapper\'s `~= false` versus `== true` behavior. Array-style settings tables such as `{true}` therefore do not act like `audio = true`. Default construction only auto-attaches a Source when the container advertises a Vorbis audio track and `love.audio` is loaded. Following the vendored wrapper path, `settings.dpiscale` defaults through the low-level `_newVideo` helper to `1.0` when omitted or nil, non-numeric `dpiscale` values surface the low-level `_newVideo` numeric error, and logical width/height follow the upstream C++ integer-truncation divide by `dpiscale`. Filter and Source-sync APIs are implemented, and drawing now routes through a Flutter-compatible media_kit bridge that prefers a persistent native texture for supported draw states, including alpha/premultiplied alpha and opaque replace/none cases, and falls back to sampled frame images for unsupported states instead of upstream LOVE\'s shader-driven YCbCr path.',
})

overrides.symbols['love.graphics.captureScreenshot'] = overrides.symbols['love.graphics.captureScreenshot'] or {}
merge_fields(overrides.symbols['love.graphics.captureScreenshot'], {
  notes = 'Queues a screenshot of the completed current frame and delivers it through LOVE-style callback, filename, or Channel targets after draw submission. Screenshot pixels are generated from the recorded screen surface using the software rasterizer, so capture fidelity matches the current canvas-backed renderer implementation. Surfaces that depend on registered Flutter fragment-asset shaders now fail with an explicit unsupported error instead of silently dropping those shader effects during software replay.',
})

overrides.symbols['Video'] = overrides.symbols['Video'] or {}
merge_fields(overrides.symbols['Video'], {
  notes = 'Compatibility Drawable/Object wrapper around a VideoStream plus optional Source synchronization. Exposes LOVE-style control, filter, and dimension queries, now stops an attached Source when the Video is released to mirror the upstream destructor, and renders through the Flutter-compatible media_kit bridge used by `love.graphics.draw`. Supported draw states use a persistent native video texture with playback commands mirrored into the host player, including alpha/premultiplied alpha and opaque replace/none blending plus quad/scissor/tint transforms, while unsupported draw states fall back to cached sampled frame snapshots and decoded Flutter images. The implementation still targets Flutter-compatible playback rather than upstream LOVE\'s dedicated YCbCr shader path.',
})

overrides.symbols['love.graphics.flushBatch'] = overrides.symbols['love.graphics.flushBatch'] or {}
merge_fields(overrides.symbols['love.graphics.flushBatch'], {
  notes = 'Compatibility no-op shim because batching is handled internally by the runtime.',
})

overrides.symbols['love.graphics.isActive'] = overrides.symbols['love.graphics.isActive'] or {}
merge_fields(overrides.symbols['love.graphics.isActive'], {
  notes = 'Fixed-response compatibility shim that reports an active graphics module in an initialized runtime.',
})

overrides.symbols['love.graphics.isGammaCorrect'] = overrides.symbols['love.graphics.isGammaCorrect'] or {}
merge_fields(overrides.symbols['love.graphics.isGammaCorrect'], {
  notes = 'Fixed-response compatibility shim that reports the current Flutter/Flame backend is not gamma-correct.',
})

overrides.symbols['love.graphics.present'] = overrides.symbols['love.graphics.present'] or {}
merge_fields(overrides.symbols['love.graphics.present'], {
  notes = 'Compatibility no-op shim because frame submission is owned by the host harness.',
})

overrides.symbols['love.graphics.validateShader'] = overrides.symbols['love.graphics.validateShader'] or {}
merge_fields(overrides.symbols['love.graphics.validateShader'], {
  status = 'partial',
  conformance = 'smoke-tested',
  notes = 'Validates source and filename inputs through the same LOVE-style resolution path and shader stage scan as `love.graphics.newShader`, preserving missing `position`/`effect` parse errors and shader-language mismatch errors before backend fallback. Mounted Flutter runtime-effect files loaded through the LOVE filesystem can infer registered fragment-asset keys relative to the mounted source root, and Flutter hosts now return `false` plus the host load error when those registered assets cannot be opened. The Flutter backend reports success for the compatibility-emulated radial gradient and desaturation-tint shader subsets plus registered Flutter fragment-asset shaders; other runtime shader source returns `false` plus an explicit unsupported-backend message because no general GLSL compiler is available.',
})

apply_symbol_overrides({
  'love.math.colorFromBytes',
  'love.math.colorToBytes',
  'love.math.gammaToLinear',
  'love.math.getRandomSeed',
  'love.math.getRandomState',
  'love.math.isConvex',
  'love.math.linearToGamma',
  'love.math.newBezierCurve',
  'love.math.newRandomGenerator',
  'love.math.newTransform',
  'love.math.noise',
  'love.math.random',
  'love.math.randomNormal',
  'love.math.setRandomSeed',
  'love.math.setRandomState',
  'love.math.triangulate',
  'BezierCurve',
  'BezierCurve:evaluate',
  'BezierCurve:getControlPoint',
  'BezierCurve:getControlPointCount',
  'BezierCurve:getDegree',
  'BezierCurve:getDerivative',
  'BezierCurve:getSegment',
  'BezierCurve:insertControlPoint',
  'BezierCurve:removeControlPoint',
  'BezierCurve:render',
  'BezierCurve:renderSegment',
  'BezierCurve:rotate',
  'BezierCurve:scale',
  'BezierCurve:setControlPoint',
  'BezierCurve:translate',
  'RandomGenerator',
  'RandomGenerator:getSeed',
  'RandomGenerator:getState',
  'RandomGenerator:random',
  'RandomGenerator:randomNormal',
  'RandomGenerator:setSeed',
  'RandomGenerator:setState',
  'Transform',
  'Transform:apply',
  'Transform:clone',
  'Transform:getMatrix',
  'Transform:inverse',
  'Transform:inverseTransformPoint',
  'Transform:isAffine2DTransform',
  'Transform:reset',
  'Transform:rotate',
  'Transform:scale',
  'Transform:setMatrix',
  'Transform:setTransformation',
  'Transform:shear',
  'Transform:transformPoint',
  'Transform:translate',
  'MatrixLayout',
  'MatrixLayout.row',
  'MatrixLayout.column',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'love.data.decode',
  'love.data.encode',
  'love.data.getPackedSize',
  'love.data.hash',
  'love.data.newByteData',
  'love.data.newDataView',
  'love.data.pack',
  'love.data.unpack',
  'ByteData',
  'CompressedData',
  'CompressedData:getFormat',
  'CompressedDataFormat',
  'CompressedDataFormat.lz4',
  'CompressedDataFormat.zlib',
  'CompressedDataFormat.gzip',
  'CompressedDataFormat.deflate',
  'ContainerType',
  'ContainerType.data',
  'ContainerType.string',
  'EncodeFormat',
  'EncodeFormat.base64',
  'EncodeFormat.hex',
  'HashFunction',
  'HashFunction.md5',
  'HashFunction.sha1',
  'HashFunction.sha224',
  'HashFunction.sha256',
  'HashFunction.sha384',
  'HashFunction.sha512',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'love.physics',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'love.physics.getDistance',
  'love.physics.getMeter',
  'love.physics.newBody',
  'love.physics.newChainShape',
  'love.physics.newCircleShape',
  'love.physics.newDistanceJoint',
  'love.physics.newEdgeShape',
  'love.physics.newFrictionJoint',
  'love.physics.newFixture',
  'love.physics.newGearJoint',
  'love.physics.newMotorJoint',
  'love.physics.newMouseJoint',
  'love.physics.newPolygonShape',
  'love.physics.newPrismaticJoint',
  'love.physics.newPulleyJoint',
  'love.physics.newRectangleShape',
  'love.physics.newRevoluteJoint',
  'love.physics.newRopeJoint',
  'love.physics.newWeldJoint',
  'love.physics.newWheelJoint',
  'love.physics.newWorld',
  'love.physics.setMeter',
  'Body',
  'Body:applyAngularImpulse',
  'Body:applyForce',
  'Body:applyLinearImpulse',
  'Body:applyTorque',
  'Body:destroy',
  'Body:getAngle',
  'Body:getAngularDamping',
  'Body:getAngularVelocity',
  'Body:getContacts',
  'Body:getFixtures',
  'Body:getGravityScale',
  'Body:getInertia',
  'Body:getJoints',
  'Body:getLinearDamping',
  'Body:getLinearVelocity',
  'Body:getLinearVelocityFromLocalPoint',
  'Body:getLinearVelocityFromWorldPoint',
  'Body:getLocalCenter',
  'Body:getLocalPoint',
  'Body:getLocalPoints',
  'Body:getLocalVector',
  'Body:getMass',
  'Body:getMassData',
  'Body:getPosition',
  'Body:getTransform',
  'Body:getType',
  'Body:getUserData',
  'Body:getWorld',
  'Body:getWorldCenter',
  'Body:getWorldPoint',
  'Body:getWorldPoints',
  'Body:getWorldVector',
  'Body:getX',
  'Body:getY',
  'Body:isActive',
  'Body:isAwake',
  'Body:isBullet',
  'Body:isDestroyed',
  'Body:isFixedRotation',
  'Body:isSleepingAllowed',
  'Body:isTouching',
  'Body:resetMassData',
  'Body:setActive',
  'Body:setAngle',
  'Body:setAngularDamping',
  'Body:setAngularVelocity',
  'Body:setAwake',
  'Body:setBullet',
  'Body:setFixedRotation',
  'Body:setGravityScale',
  'Body:setInertia',
  'Body:setLinearDamping',
  'Body:setLinearVelocity',
  'Body:setMass',
  'Body:setMassData',
  'Body:setPosition',
  'Body:setSleepingAllowed',
  'Body:setTransform',
  'Body:setType',
  'Body:setUserData',
  'Body:setX',
  'Body:setY',
  'BodyType',
  'BodyType.static',
  'BodyType.dynamic',
  'BodyType.kinematic',
  'ChainShape',
  'ChainShape:getChildEdge',
  'ChainShape:getNextVertex',
  'ChainShape:getPoint',
  'ChainShape:getPoints',
  'ChainShape:getPreviousVertex',
  'ChainShape:getVertexCount',
  'ChainShape:setNextVertex',
  'ChainShape:setPreviousVertex',
  'Contact',
  'Contact:getChildren',
  'Contact:getFixtures',
  'Contact:getFriction',
  'Contact:getNormal',
  'Contact:getPositions',
  'Contact:getRestitution',
  'Contact:getTangentSpeed',
  'Contact:isEnabled',
  'Contact:isTouching',
  'Contact:resetFriction',
  'Contact:resetRestitution',
  'Contact:setEnabled',
  'Contact:setFriction',
  'Contact:setRestitution',
  'Contact:setTangentSpeed',
  'CircleShape',
  'CircleShape:getPoint',
  'CircleShape:getRadius',
  'CircleShape:setPoint',
  'CircleShape:setRadius',
  'DistanceJoint',
  'DistanceJoint:getDampingRatio',
  'DistanceJoint:getFrequency',
  'DistanceJoint:getLength',
  'DistanceJoint:setDampingRatio',
  'DistanceJoint:setFrequency',
  'DistanceJoint:setLength',
  'EdgeShape',
  'EdgeShape:getNextVertex',
  'EdgeShape:getPoints',
  'EdgeShape:getPreviousVertex',
  'EdgeShape:setNextVertex',
  'EdgeShape:setPreviousVertex',
  'Fixture',
  'Fixture:destroy',
  'Fixture:getBody',
  'Fixture:getBoundingBox',
  'Fixture:getCategory',
  'Fixture:getDensity',
  'Fixture:getFilterData',
  'Fixture:getFriction',
  'Fixture:getGroupIndex',
  'Fixture:getMask',
  'Fixture:getMassData',
  'Fixture:getRestitution',
  'Fixture:getShape',
  'Fixture:getUserData',
  'Fixture:isDestroyed',
  'Fixture:isSensor',
  'Fixture:rayCast',
  'Fixture:setCategory',
  'Fixture:setDensity',
  'Fixture:setFilterData',
  'Fixture:setFriction',
  'Fixture:setGroupIndex',
  'Fixture:setMask',
  'Fixture:setRestitution',
  'Fixture:setSensor',
  'Fixture:setUserData',
  'Fixture:testPoint',
  'FrictionJoint',
  'FrictionJoint:getMaxForce',
  'FrictionJoint:getMaxTorque',
  'FrictionJoint:setMaxForce',
  'FrictionJoint:setMaxTorque',
  'GearJoint',
  'GearJoint:getJoints',
  'GearJoint:getRatio',
  'GearJoint:setRatio',
  'Joint',
  'Joint:destroy',
  'Joint:getAnchors',
  'Joint:getBodies',
  'Joint:getCollideConnected',
  'Joint:getReactionForce',
  'Joint:getReactionTorque',
  'Joint:getType',
  'Joint:getUserData',
  'Joint:isDestroyed',
  'Joint:setUserData',
  'JointType',
  'JointType.distance',
  'JointType.friction',
  'JointType.gear',
  'JointType.mouse',
  'JointType.prismatic',
  'JointType.pulley',
  'JointType.revolute',
  'JointType.rope',
  'MotorJoint',
  'MotorJoint:getAngularOffset',
  'MotorJoint:getLinearOffset',
  'MotorJoint:setAngularOffset',
  'MotorJoint:setLinearOffset',
  'MouseJoint',
  'MouseJoint:getDampingRatio',
  'MouseJoint:getFrequency',
  'MouseJoint:getMaxForce',
  'MouseJoint:getTarget',
  'MouseJoint:setDampingRatio',
  'MouseJoint:setFrequency',
  'MouseJoint:setMaxForce',
  'MouseJoint:setTarget',
  'PrismaticJoint',
  'PrismaticJoint:areLimitsEnabled',
  'PrismaticJoint:getAxis',
  'PrismaticJoint:getJointSpeed',
  'PrismaticJoint:getJointTranslation',
  'PrismaticJoint:getLimits',
  'PrismaticJoint:getLowerLimit',
  'PrismaticJoint:getMaxMotorForce',
  'PrismaticJoint:getMotorForce',
  'PrismaticJoint:getMotorSpeed',
  'PrismaticJoint:getReferenceAngle',
  'PrismaticJoint:getUpperLimit',
  'PrismaticJoint:isMotorEnabled',
  'PrismaticJoint:setLimits',
  'PrismaticJoint:setLimitsEnabled',
  'PrismaticJoint:setLowerLimit',
  'PrismaticJoint:setMaxMotorForce',
  'PrismaticJoint:setMotorEnabled',
  'PrismaticJoint:setMotorSpeed',
  'PrismaticJoint:setUpperLimit',
  'PulleyJoint',
  'PulleyJoint:getConstant',
  'PulleyJoint:getGroundAnchors',
  'PulleyJoint:getLengthA',
  'PulleyJoint:getLengthB',
  'PulleyJoint:getMaxLengths',
  'PulleyJoint:getRatio',
  'PulleyJoint:setConstant',
  'PulleyJoint:setMaxLengths',
  'PulleyJoint:setRatio',
  'JointType.weld',
  'PolygonShape',
  'PolygonShape:getPoints',
  'RevoluteJoint',
  'RevoluteJoint:areLimitsEnabled',
  'RevoluteJoint:getJointAngle',
  'RevoluteJoint:getJointSpeed',
  'RevoluteJoint:getLimits',
  'RevoluteJoint:getLowerLimit',
  'RevoluteJoint:getMaxMotorTorque',
  'RevoluteJoint:getMotorSpeed',
  'RevoluteJoint:getMotorTorque',
  'RevoluteJoint:getReferenceAngle',
  'RevoluteJoint:getUpperLimit',
  'RevoluteJoint:hasLimitsEnabled',
  'RevoluteJoint:isMotorEnabled',
  'RevoluteJoint:setLimits',
  'RevoluteJoint:setLimitsEnabled',
  'RevoluteJoint:setLowerLimit',
  'RevoluteJoint:setMaxMotorTorque',
  'RevoluteJoint:setMotorEnabled',
  'RevoluteJoint:setMotorSpeed',
  'RevoluteJoint:setUpperLimit',
  'RopeJoint',
  'RopeJoint:getMaxLength',
  'RopeJoint:setMaxLength',
  'Shape',
  'Shape:computeAABB',
  'Shape:computeMass',
  'Shape:getChildCount',
  'Shape:getRadius',
  'Shape:getType',
  'Shape:rayCast',
  'Shape:testPoint',
  'ShapeType',
  'ShapeType.circle',
  'ShapeType.polygon',
  'ShapeType.edge',
  'ShapeType.chain',
  'WeldJoint',
  'WeldJoint:getDampingRatio',
  'WeldJoint:getFrequency',
  'WeldJoint:getReferenceAngle',
  'WeldJoint:setDampingRatio',
  'WeldJoint:setFrequency',
  'WheelJoint',
  'WheelJoint:getAxis',
  'WheelJoint:getJointSpeed',
  'WheelJoint:getJointTranslation',
  'WheelJoint:getMaxMotorTorque',
  'WheelJoint:getMotorSpeed',
  'WheelJoint:getMotorTorque',
  'WheelJoint:getSpringDampingRatio',
  'WheelJoint:getSpringFrequency',
  'WheelJoint:isMotorEnabled',
  'WheelJoint:setMaxMotorTorque',
  'WheelJoint:setMotorEnabled',
  'WheelJoint:setMotorSpeed',
  'WheelJoint:setSpringDampingRatio',
  'WheelJoint:setSpringFrequency',
  'World',
  'World:destroy',
  'World:getBodies',
  'World:getBodyCount',
  'World:getContactCount',
  'World:getContacts',
  'World:getGravity',
  'World:getJointCount',
  'World:getJoints',
  'World:isDestroyed',
  'World:isLocked',
  'World:isSleepingAllowed',
  'World:queryBoundingBox',
  'World:rayCast',
  'World:setGravity',
  'World:setSleepingAllowed',
  'World:translateOrigin',
  'World:update',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'Body:getContactList',
  'Body:getFixtureList',
  'Body:getJointList',
  'Contact:isDestroyed',
  'Fixture:getType',
  'MotorJoint:getCorrectionFactor',
  'MotorJoint:getMaxForce',
  'MotorJoint:getMaxTorque',
  'MotorJoint:setCorrectionFactor',
  'MotorJoint:setMaxForce',
  'MotorJoint:setMaxTorque',
  'PolygonShape:validate',
  'PrismaticJoint:hasLimitsEnabled',
  'World:getBodyList',
  'World:getContactList',
  'World:getJointList',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

add_extra_symbol(
  'love.graphics',
  'ParticleSystem:getAreaSpread',
  'method',
  'ParticleSystem',
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed deprecated alias for `ParticleSystem:getEmissionArea`. The runtime mirrors the upstream wrapper by returning only the distribution, x spread, and y spread, and the vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

add_extra_symbol(
  'love.graphics',
  'ParticleSystem:setAreaSpread',
  'method',
  'ParticleSystem',
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed deprecated alias for `ParticleSystem:setEmissionArea`. The runtime mirrors the upstream wrapper by forcing angle `0` and `directionRelativeToCenter = false`, and the vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

add_extra_symbol(
  'love.graphics',
  'Quad:getLayer',
  'method',
  'Quad',
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed LOVE Quad method returning the 1-based array-texture layer configured on the Quad. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.graphics',
  'Quad:setLayer',
  'method',
  'Quad',
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed LOVE Quad method storing the 1-based array-texture layer used by love.graphics.draw and SpriteBatch:add/set when an Array Texture is paired with the Quad. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.graphics',
  'SpriteBatch:getDrawRange',
  'method',
  'SpriteBatch',
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed LOVE SpriteBatch method returning the active 1-based draw-range start and count, or nil when no range override is set. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.graphics',
  'Video:getPixelDimensions',
  'method',
  'Video',
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed LOVE Video method returning the underlying decoded frame width and height in pixels, distinct from logical dimensions when `dpiscale` is used. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.graphics',
  'Video:getPixelHeight',
  'method',
  'Video',
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed LOVE Video method returning the underlying decoded frame height in pixels, distinct from logical height when `dpiscale` is used. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.graphics',
  'Video:getPixelWidth',
  'method',
  'Video',
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed LOVE Video method returning the underlying decoded frame width in pixels, distinct from logical width when `dpiscale` is used. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.graphics',
  'Video:_setSource',
  'method',
  'Video',
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed low-level Video helper omitted by the vendored `third_party/love-api` inventory even though the vendored LOVE C++ wrapper exposes it and `wrap_Video.lua` builds the public `Video:setSource` behavior on top of it. It updates only the stored Source reference and intentionally does not modify the VideoStream sync target.',
  }
)

add_extra_symbol(
  'love.graphics',
  'love.graphics.isCreated',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'shimmed',
    conformance = 'smoke-tested',
    notes = 'Source-backed graphics-module initialization query. The runtime exposes it as a fixed-response shim that reports an initialized graphics module, and the vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.graphics',
  'love.graphics.getDefaultMipmapFilter',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed graphics-module default mipmap-filter query. The runtime tracks the current default mipmap filter and sharpness in graphics state, applies them to newly created mipmapped Images and Canvases, and the vendored `third_party/love-api` inventory omits this function even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.graphics',
  'love.graphics.setDefaultMipmapFilter',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed graphics-module default mipmap-filter mutator. The runtime stores the current default mipmap filter and sharpness in graphics state, applies them to newly created mipmapped Images and Canvases, and the vendored `third_party/love-api` inventory omits this function even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'Body:getFixtureList',
  'method',
  'Body',
  {
    notes = 'Source-backed deprecated alias for `Body:getFixtures`. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'Body:getJointList',
  'method',
  'Body',
  {
    notes = 'Source-backed deprecated alias for `Body:getJoints`. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'Body:getContactList',
  'method',
  'Body',
  {
    notes = 'Source-backed deprecated alias for `Body:getContacts`. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'Contact:getTangentSpeed',
  'method',
  'Contact',
  {
    notes = 'Source-backed LOVE Contact method bridged directly onto Forge2D\'s native tangent-speed field getter. The vendored `third_party/love-api` inventory omits this method even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'Contact:setTangentSpeed',
  'method',
  'Contact',
  {
    notes = 'Source-backed LOVE Contact method bridged directly onto Forge2D\'s native tangent-speed field setter. Direct calls and queued `preSolve` callbacks both affect later solver steps. The vendored `third_party/love-api` inventory omits this method even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'Contact:isDestroyed',
  'method',
  'Contact',
  {
    notes = 'Source-backed LOVE Contact destruction-state query. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'Fixture:getType',
  'method',
  'Fixture',
  {
    notes = 'Source-backed LOVE Fixture method returning the attached Shape type name. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'MotorJoint:getCorrectionFactor',
  'method',
  'MotorJoint',
  {
    notes = 'Source-backed LOVE MotorJoint method bridged onto Forge2D\'s correction-factor getter. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'MotorJoint:getMaxForce',
  'method',
  'MotorJoint',
  {
    notes = 'Source-backed LOVE MotorJoint method bridged onto Forge2D\'s max-force getter. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'MotorJoint:getMaxTorque',
  'method',
  'MotorJoint',
  {
    notes = 'Source-backed LOVE MotorJoint method bridged onto Forge2D\'s max-torque getter. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'MotorJoint:setCorrectionFactor',
  'method',
  'MotorJoint',
  {
    notes = 'Source-backed LOVE MotorJoint method bridged onto Forge2D\'s correction-factor setter. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'MotorJoint:setMaxForce',
  'method',
  'MotorJoint',
  {
    notes = 'Source-backed LOVE MotorJoint method bridged onto Forge2D\'s max-force setter. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'MotorJoint:setMaxTorque',
  'method',
  'MotorJoint',
  {
    notes = 'Source-backed LOVE MotorJoint method bridged onto Forge2D\'s max-torque setter. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'PolygonShape:validate',
  'method',
  'PolygonShape',
  {
    notes = 'Source-backed LOVE PolygonShape method bridged onto Forge2D polygon validation. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'PrismaticJoint:hasLimitsEnabled',
  'method',
  'PrismaticJoint',
  {
    notes = 'Source-backed deprecated alias for `PrismaticJoint:areLimitsEnabled`. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'World:getBodyList',
  'method',
  'World',
  {
    notes = 'Source-backed deprecated alias for `World:getBodies`. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'World:getJointList',
  'method',
  'World',
  {
    notes = 'Source-backed deprecated alias for `World:getJoints`. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

add_extra_symbol(
  'love.physics',
  'World:getContactList',
  'method',
  'World',
  {
    notes = 'Source-backed deprecated alias for `World:getContacts`. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

apply_symbol_overrides({
  'love.data.compress',
  'love.data.decompress',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
  notes = 'Implemented for zlib, gzip, deflate, and LOVE-compatible LZ4 blocks. LZ4 payloads use the same 4-byte little-endian uncompressed-size header as upstream LOVE, and the current encoder favors interoperable output over native liblz4 ratio parity.',
})

apply_symbol_overrides({
  'World:getCallbacks',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
  notes = 'Returns the currently registered world collision callbacks, including when called from Lua coroutines.',
})

apply_symbol_overrides({
  'World:setCallbacks',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
  notes = 'Collision callbacks dispatch synchronously while Forge2D steps in the AST runtime path used by the LOVE bindings, so world:isLocked() is true during callback execution and preSolve contact enable, friction, restitution, and tangent-speed mutations can affect the current solver pass. Like upstream Box2D-style stepping, continuous-collision processing can surface multiple preSolve and postSolve callbacks for the same contact within a single World:update.',
})

apply_symbol_overrides({
  'World:getContactFilter',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
  notes = 'Returns the currently registered contact-filter callback, including when called from Lua coroutines.',
})

apply_symbol_overrides({
  'World:setContactFilter',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
  notes = 'The Lua filter callback dispatches synchronously from Forge2D\'s contact filter in the AST runtime path used by the LOVE bindings, covering refiltering and mid-step contacts driven by linear velocity, gravity and applied forces, and angular motion. Like upstream Box2D-style broad-phase processing, the same fixture pair can be evaluated multiple times within a single World:update.',
})

apply_symbol_overrides({
  'love.event',
  'love.event.clear',
  'love.event.poll',
  'love.event.pump',
  'love.event.push',
  'love.event.quit',
  'love.event.wait',
  'Event',
  'Event.focus',
  'Event.joystickpressed',
  'Event.joystickreleased',
  'Event.keypressed',
  'Event.keyreleased',
  'Event.mousepressed',
  'Event.mousereleased',
  'Event.quit',
  'Event.resize',
  'Event.visible',
  'Event.mousefocus',
  'Event.threaderror',
  'Event.joystickadded',
  'Event.joystickremoved',
  'Event.joystickaxis',
  'Event.joystickhat',
  'Event.gamepadpressed',
  'Event.gamepadreleased',
  'Event.gamepadaxis',
  'Event.textinput',
  'Event.mousemoved',
  'Event.lowmemory',
  'Event.textedited',
  'Event.wheelmoved',
  'Event.touchpressed',
  'Event.touchreleased',
  'Event.touchmoved',
  'Event.directorydropped',
  'Event.filedropped',
  'Event.jp',
  'Event.jr',
  'Event.kp',
  'Event.kr',
  'Event.mp',
  'Event.mr',
  'Event.q',
  'Event.f',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'love',
  'love.getVersion',
  'love.hasDeprecationOutput',
  'love.isVersionCompatible',
  'love.setDeprecationOutput',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

overrides.symbols['love'] = overrides.symbols['love'] or {}
merge_fields(overrides.symbols['love'], {
  status = 'implemented',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'love.load',
  'love.update',
  'love.draw',
  'love.errorhandler',
  'love.run',
  'love.conf',
  'love.quit',
  'love.resize',
  'love.lowmemory',
  'love.visible',
  'love.directorydropped',
  'love.displayrotated',
  'love.filedropped',
  'love.threaderror',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

overrides.symbols['love.run'] = overrides.symbols['love.run'] or {}
merge_fields(overrides.symbols['love.run'], {
  notes = 'Default LOVE main-loop semantics are implemented, including love.load bootstrap, queued event dispatch, love.quit abort and exit handling, timer stepping, per-frame origin reset before draw, and host-backed sleep pacing. love.arg.parseGameArguments is used when available, and the raw arg table is still forwarded as the second love.load argument.',
})

overrides.symbols['love.errorhandler'] = overrides.symbols['love.errorhandler'] or {}
merge_fields(overrides.symbols['love.errorhandler'], {
  notes = 'Default LOVE error-handler semantics are implemented through a runtime-managed error loop that resets input and graphics state, renders an error screen, supports clipboard copy shortcuts, and is invoked automatically by the Flame harness when LOVE callbacks fail. User-defined love.errorhandler overrides are also honored.',
})

overrides.symbols['love.conf'] = overrides.symbols['love.conf'] or {}
merge_fields(overrides.symbols['love.conf'], {
  notes = 'Configuration bootstrap is implemented before main.lua execution, including filesystem identity, window metrics, audio mix-with-system state, and module disabling.',
})

overrides.symbols['love.quit'] = overrides.symbols['love.quit'] or {}
merge_fields(overrides.symbols['love.quit'], {
  notes = 'Runtime quit callback invocation is implemented, including harness-side handling for aborting queued quits when the callback returns true and restarting when the queued quit status is "restart".',
})

overrides.symbols['love.resize'] = overrides.symbols['love.resize'] or {}
merge_fields(overrides.symbols['love.resize'], {
  notes = 'Runtime resize callback dispatch is implemented, including Flame harness viewport-change integration and matching love.event queue entries.',
})

overrides.symbols['love.lowmemory'] = overrides.symbols['love.lowmemory'] or {}
merge_fields(overrides.symbols['love.lowmemory'], {
  notes = 'Runtime low-memory callback dispatch is implemented, including Flame harness forwarding from Flutter memory-pressure notifications.',
})

overrides.symbols['love.visible'] = overrides.symbols['love.visible'] or {}
merge_fields(overrides.symbols['love.visible'], {
  notes = 'Runtime visibility callback dispatch is implemented, including Flame harness forwarding from Flutter app lifecycle visibility changes.',
})

overrides.symbols['love.directorydropped'] = overrides.symbols['love.directorydropped'] or {}
merge_fields(overrides.symbols['love.directorydropped'], {
  notes = 'Runtime callback helpers and LOVE event queue dispatch are implemented. Direct platform drop-event wiring remains integration-specific.',
})

overrides.symbols['love.displayrotated'] = overrides.symbols['love.displayrotated'] or {}
merge_fields(overrides.symbols['love.displayrotated'], {
  notes = 'Runtime callback helpers and LOVE event queue dispatch are implemented. Direct platform orientation-change wiring remains integration-specific.',
})

overrides.symbols['love.filedropped'] = overrides.symbols['love.filedropped'] or {}
merge_fields(overrides.symbols['love.filedropped'], {
  notes = 'Runtime callback helpers and LOVE event queue dispatch are implemented, including DroppedFile wrapping. Direct platform drop-event wiring remains integration-specific.',
})

overrides.symbols['love.threaderror'] = overrides.symbols['love.threaderror'] or {}
merge_fields(overrides.symbols['love.threaderror'], {
  notes = 'Runtime callback helpers and LOVE event queue dispatch are implemented for threaderror payloads.',
})

apply_symbol_overrides({
  'Data',
  'Data:clone',
  'Data:getPointer',
  'Data:getSize',
  'Data:getString',
  'Object',
  'Object:release',
  'Object:type',
  'Object:typeOf',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

overrides.symbols['Object:release'] = overrides.symbols['Object:release'] or {}
merge_fields(overrides.symbols['Object:release'], {
  notes = 'Shared base-object release contract used by the implemented wrapper types. Release is idempotent and returns `true` the first time and `false` on later calls. The released Lua wrapper is invalidated so later method calls stop treating it as a live object, and wrappers with owned runtime resources such as `Source`, `Video`, and `VideoStream` also dispose or detach their backing runtime state during the first release.',
})

overrides.symbols['Data:getFFIPointer'] = overrides.symbols['Data:getFFIPointer'] or {}
merge_fields(overrides.symbols['Data:getFFIPointer'], {
  status = 'implemented',
  conformance = 'smoke-tested',
  notes = 'Exposed as the same compatibility pointer handle as Data:getPointer in the Dart runtime, since LuaJIT FFI cdata pointers are not available here.',
})

apply_symbol_overrides({
  'love.filesystem.append',
  'love.filesystem.areSymlinksEnabled',
  'love.filesystem.createDirectory',
  'love.filesystem.getAppdataDirectory',
  'love.filesystem.getCRequirePath',
  'love.filesystem.getDirectoryItems',
  'love.filesystem.getIdentity',
  'love.filesystem.getInfo',
  'love.filesystem.getRealDirectory',
  'love.filesystem.getRequirePath',
  'love.filesystem.getSaveDirectory',
  'love.filesystem.getSource',
  'love.filesystem.getSourceBaseDirectory',
  'love.filesystem.getUserDirectory',
  'love.filesystem.getWorkingDirectory',
  'love.filesystem.init',
  'love.filesystem.isFused',
  'love.filesystem.lines',
  'love.filesystem.load',
  'love.filesystem.newFile',
  'love.filesystem.newFileData',
  'love.filesystem.read',
  'love.filesystem.remove',
  'love.filesystem.setCRequirePath',
  'love.filesystem.setIdentity',
  'love.filesystem.setRequirePath',
  'love.filesystem.setSource',
  'love.filesystem.setSymlinksEnabled',
  'love.filesystem.unmount',
  'love.filesystem.write',
  'File:close',
  'File:flush',
  'File:getBuffer',
  'File:getExtension',
  'File:getFilename',
  'File:getMode',
  'File:getSize',
  'File:isEOF',
  'File:isOpen',
  'File:lines',
  'File:open',
  'File:read',
  'File:seek',
  'File:setBuffer',
  'File:tell',
  'File:write',
  'FileData:clone',
  'FileData:getExtension',
  'FileData:getFilename',
  'BufferMode',
  'BufferMode.none',
  'BufferMode.line',
  'BufferMode.full',
  'FileDecoder',
  'FileDecoder.file',
  'FileDecoder.base64',
  'FileMode',
  'FileMode.r',
  'FileMode.w',
  'FileMode.a',
  'FileMode.c',
  'FileType',
  'FileType.file',
  'FileType.directory',
  'FileType.symlink',
  'FileType.other',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

overrides.symbols['love.filesystem.mount'] = overrides.symbols['love.filesystem.mount'] or {}
merge_fields(overrides.symbols['love.filesystem.mount'], {
  status = 'partial',
  conformance = 'smoke-tested',
  notes = 'Logical directory mounts, mounted-module loading, and zip, tar-family, grp/qpak, hog, mvl, slb, vdf, wad, iso, and 7z archive mounts from direct filesystem paths, logical source/save-relative paths, host-provided DroppedFile wrappers, FileData, and generic Data wrappers are implemented. 7z archives whose file data and encoded headers, when present, use single-folder Copy, LZMA, or LZMA2 coder chains are decoded in pure Dart across platforms. More advanced 7z layouts such as multi-coder or multi-pack-stream folders still fall back to a host `7z`/`7za`/`7zr` tool on IO platforms and remain unsupported elsewhere, so full cross-platform parity remains partial.',
})

apply_symbol_overrides({
  'File',
  'FileData',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

overrides.symbols['DroppedFile'] = overrides.symbols['DroppedFile'] or {}
merge_fields(overrides.symbols['DroppedFile'], {
  status = 'implemented',
  conformance = 'smoke-tested',
  notes = 'Filesystem-side DroppedFile wrapper semantics are implemented, including File subtype behavior, mount support, and acquisition through love.filedropped callback dispatch and queued LOVE events. Direct platform drop-event wiring remains integration-specific.',
})

overrides.symbols['love.sound.newDecoder'] = overrides.symbols['love.sound.newDecoder'] or {}
merge_fields(overrides.symbols['love.sound.newDecoder'], {
  status = 'partial',
  conformance = 'smoke-tested',
  notes = 'LOVE-style decoder construction and Decoder methods are implemented. Encoded input support covers WAV containers in pure Dart, including PCM and IEEE float variants, and additionally decodes recognized Ogg, MP3, and FLAC payloads through a host `ffmpeg` fallback on IO platforms when available.',
})

overrides.symbols['love.sound.newSoundData'] = overrides.symbols['love.sound.newSoundData'] or {}
merge_fields(overrides.symbols['love.sound.newSoundData'], {
  status = 'partial',
  conformance = 'smoke-tested',
  notes = 'Numeric SoundData construction is implemented, and decoder/file overloads work through the runtime decoder bridge. Encoded input support covers WAV containers in pure Dart, including PCM and IEEE float variants, and additionally decodes recognized Ogg, MP3, and FLAC payloads through a host `ffmpeg` fallback on IO platforms when available.',
})

add_extra_symbol(
  'love.graphics',
  'love.graphics._shaderCodeToGLSL',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed graphics shader translation helper omitted by the vendored `third_party/love-api` inventory even though the vendored LOVE shader wrapper exposes it. The runtime now ports LOVE\'s stage-classification and GLSL scaffolding generator, including language pragma handling, custom pixel shader support, and multi-canvas output scaffolding, while still treating the generated GLSL as an inspection/parity artifact rather than something the Flutter backend can compile dynamically.',
  }
)

add_extra_symbol(
  'love.graphics',
  'love.graphics._setDefaultShaderCode',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'shimmed',
    conformance = 'smoke-tested',
    notes = 'Source-backed low-level graphics shader bootstrap helper omitted by the vendored `third_party/love-api` inventory even though the vendored LOVE graphics shader wrapper calls it during startup. The runtime validates the upstream nested shader-code table shape and then ignores the payload because the Dart/Flutter backend does not compile or consume LOVE\'s generated default GLSL pipeline.',
  }
)

add_extra_symbol(
  'love.graphics',
  'love.graphics._transformGLSLErrorMessages',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed graphics shader helper omitted by the vendored `third_party/love-api` inventory even though the vendored LOVE shader wrapper exposes it. The runtime mirrors the upstream message rewriter for known NVIDIA, AMD, and macOS-style GLSL compiler error formats and passes unknown messages through unchanged.',
  }
)

add_extra_symbol(
  'love.graphics',
  'love.graphics._newVideo',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed low-level graphics video constructor omitted by the vendored `third_party/love-api` inventory even though the vendored LOVE wrapper exposes it and `love.graphics.newVideo` is built on top of it in `wrap_Graphics.lua`. The runtime forwards it into the compatibility `newVideo` path with upstream-style low-level semantics: no audio wiring and a numeric `dpiscale` argument defaulting to `1.0` when omitted or nil.',
  }
)

add_extra_symbol(
  'love.event',
  'love.event.poll_i',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed low-level event iterator helper omitted by the vendored `third_party/love-api` inventory even though the vendored LOVE wrapper exposes it and `love.event.poll()` returns it. The runtime exposes it directly on the module table with the same per-call event polling behavior.',
  }
)

add_extra_symbol(
  'love.filesystem',
  'love.filesystem.setFused',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed filesystem configuration helper exposed by the vendored LOVE C++ wrapper but omitted by the vendored `third_party/love-api` inventory. The runtime mirrors upstream by toggling fused mode on the filesystem state.',
  }
)

add_extra_symbol(
  'love.filesystem',
  'love.filesystem._setAndroidSaveExternal',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed Android-specific filesystem helper exposed by the vendored LOVE C++ wrapper but omitted by the vendored `third_party/love-api` inventory. The runtime stores the upstream-compatible external-save preference on filesystem state.',
  }
)

add_extra_symbol(
  'love.filesystem',
  'love.filesystem.getExecutablePath',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed filesystem path query exposed by the vendored LOVE C++ wrapper but omitted by the vendored `third_party/love-api` inventory. The runtime returns the adapter-provided executable path, or an empty string when unavailable.',
  }
)

add_extra_symbol(
  'love.filesystem',
  'love.filesystem.exists',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed deprecated alias for `love.filesystem.getInfo`. The runtime mirrors upstream by returning whether the path resolves through the LOVE filesystem state, and the vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

add_extra_symbol(
  'love.filesystem',
  'love.filesystem.isDirectory',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed deprecated alias for `love.filesystem.getInfo`. The runtime mirrors upstream by checking for a directory node type through the LOVE filesystem state, and the vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

add_extra_symbol(
  'love.filesystem',
  'love.filesystem.isFile',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed deprecated alias for `love.filesystem.getInfo`. The runtime mirrors upstream by checking for a file node type through the LOVE filesystem state, and the vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

add_extra_symbol(
  'love.filesystem',
  'love.filesystem.isSymlink',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed deprecated alias for `love.filesystem.getInfo`. The runtime mirrors upstream by checking for a symlink node type through the LOVE filesystem state, and the vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

add_extra_symbol(
  'love.filesystem',
  'love.filesystem.getLastModified',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed deprecated alias for `love.filesystem.getInfo`. The runtime mirrors upstream error semantics for missing paths and unknown modification times, and the vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

add_extra_symbol(
  'love.filesystem',
  'love.filesystem.getSize',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed deprecated alias for `love.filesystem.getInfo`. The runtime mirrors upstream error semantics for missing paths, unknown sizes, and values too large for Lua numbers, and the vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

add_extra_symbol(
  'love.image',
  'love.image.newCubeFaces',
  'function',
  nil,
  {
    phase = 'high',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed image-module cubemap layout extractor. The runtime mirrors the upstream wrapper by splitting packed cubemap ImageData layouts into 6 ImageData return values in LOVE cubemap face order, and the vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.image',
  'ImageData:clone',
  'method',
  'ImageData',
  {
    phase = 'high',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed ImageData clone method. The runtime returns an independent copy of the pixel data, and the vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.image',
  'CompressedImageData:clone',
  'method',
  'CompressedImageData',
  {
    phase = 'high',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed CompressedImageData clone method. The runtime returns an independent copy of the compressed payload metadata and bytes, and the vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper exposes it.',
  }
)

add_extra_symbol(
  'love.audio',
  'love.audio.getSourceCount',
  'function',
  nil,
  {
    phase = 'high',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed deprecated alias for `love.audio.getActiveSourceCount`. The runtime forwards it to the active-source-count query, and the vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

add_extra_symbol(
  'love.audio',
  'Source:getChannels',
  'method',
  'Source',
  {
    phase = 'high',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed deprecated alias for `Source:getChannelCount`. The runtime forwards it to the same channel-count state, and the vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

add_extra_symbol(
  'love.window',
  'love.window.getNativeDPIScale',
  'function',
  nil,
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed window DPI query omitted by the vendored `third_party/love-api` inventory even though the vendored LOVE C++ wrapper exposes it. The current Flutter window bridge exposes a single DPI scale value, so the runtime returns the same host-managed scale as `love.window.getDPIScale`.',
  }
)

add_extra_symbol(
  'love.sound',
  'Decoder:getChannels',
  'method',
  'Decoder',
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed deprecated alias for `Decoder:getChannelCount`. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

add_extra_symbol(
  'love.sound',
  'SoundData:getChannels',
  'method',
  'SoundData',
  {
    phase = 'foundation',
    status = 'implemented',
    conformance = 'smoke-tested',
    notes = 'Source-backed deprecated alias for `SoundData:getChannelCount`. The vendored `third_party/love-api` inventory omits it even though the vendored LOVE C++ wrapper still exposes it.',
  }
)

apply_symbol_overrides({
  'love.joystick.getGamepadMappingString',
  'love.joystick.getJoystickCount',
  'love.joystick.getJoysticks',
  'love.joystick.loadGamepadMappings',
  'love.joystick.saveGamepadMappings',
  'love.joystick.setGamepadMapping',
  'Joystick:getAxes',
  'Joystick:getAxis',
  'Joystick:getAxisCount',
  'Joystick:getButtonCount',
  'Joystick:getDeviceInfo',
  'Joystick:getGUID',
  'Joystick:getGamepadAxis',
  'Joystick:getGamepadMapping',
  'Joystick:getGamepadMappingString',
  'Joystick:getHat',
  'Joystick:getHatCount',
  'Joystick:getID',
  'Joystick:getName',
  'Joystick:getVibration',
  'Joystick:isConnected',
  'Joystick:isDown',
  'Joystick:isGamepad',
  'Joystick:isGamepadDown',
  'Joystick:isVibrationSupported',
  'Joystick:setVibration',
  'GamepadAxis',
  'GamepadAxis.leftx',
  'GamepadAxis.lefty',
  'GamepadAxis.rightx',
  'GamepadAxis.righty',
  'GamepadAxis.triggerleft',
  'GamepadAxis.triggerright',
  'GamepadButton',
  'GamepadButton.a',
  'GamepadButton.b',
  'GamepadButton.x',
  'GamepadButton.y',
  'GamepadButton.back',
  'GamepadButton.guide',
  'GamepadButton.start',
  'GamepadButton.leftstick',
  'GamepadButton.rightstick',
  'GamepadButton.leftshoulder',
  'GamepadButton.rightshoulder',
  'GamepadButton.dpup',
  'GamepadButton.dpdown',
  'GamepadButton.dpleft',
  'GamepadButton.dpright',
  'JoystickHat',
  'JoystickHat.c',
  'JoystickHat.d',
  'JoystickHat.l',
  'JoystickHat.ld',
  'JoystickHat.lu',
  'JoystickHat.r',
  'JoystickHat.rd',
  'JoystickHat.ru',
  'JoystickHat.u',
  'JoystickInputType',
  'JoystickInputType.axis',
  'JoystickInputType.button',
  'JoystickInputType.hat',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'love.system.getClipboardText',
  'love.system.getOS',
  'love.system.getPowerInfo',
  'love.system.getProcessorCount',
  'love.system.hasBackgroundMusic',
  'love.system.openURL',
  'love.system.setClipboardText',
  'love.system.vibrate',
  'PowerState',
  'PowerState.unknown',
  'PowerState.battery',
  'PowerState.nobattery',
  'PowerState.charging',
  'PowerState.charged',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'love.window.close',
  'love.window.fromPixels',
  'love.window.getDPIScale',
  'love.window.getDesktopDimensions',
  'love.window.getDisplayCount',
  'love.window.getDisplayName',
  'love.window.getDisplayOrientation',
  'love.window.getFullscreen',
  'love.window.getFullscreenModes',
  'love.window.getIcon',
  'love.window.getMode',
  'love.window.getPosition',
  'love.window.getSafeArea',
  'love.window.getTitle',
  'love.window.getVSync',
  'love.window.hasFocus',
  'love.window.hasMouseFocus',
  'love.window.isDisplaySleepEnabled',
  'love.window.isMaximized',
  'love.window.isMinimized',
  'love.window.isOpen',
  'love.window.isVisible',
  'love.window.maximize',
  'love.window.minimize',
  'love.window.requestAttention',
  'love.window.restore',
  'love.window.setDisplaySleepEnabled',
  'love.window.setFullscreen',
  'love.window.setIcon',
  'love.window.setMode',
  'love.window.setPosition',
  'love.window.setTitle',
  'love.window.setVSync',
  'love.window.showMessageBox',
  'love.window.toPixels',
  'love.window.updateMode',
  'DisplayOrientation',
  'DisplayOrientation.unknown',
  'DisplayOrientation.landscape',
  'DisplayOrientation.landscapeflipped',
  'DisplayOrientation.portrait',
  'DisplayOrientation.portraitflipped',
  'FullscreenType',
  'FullscreenType.desktop',
  'FullscreenType.exclusive',
  'FullscreenType.normal',
  'MessageBoxType',
  'MessageBoxType.info',
  'MessageBoxType.warning',
  'MessageBoxType.error',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'love.timer',
  'love.timer.getAverageDelta',
  'love.timer.getDelta',
  'love.timer.getFPS',
  'love.timer.getTime',
  'love.timer.sleep',
  'love.timer.step',
  'love.touch',
  'love.touch.getPosition',
  'love.touch.getPressure',
  'love.touch.getTouches',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'love.focus',
  'love.gamepadaxis',
  'love.gamepadpressed',
  'love.gamepadreleased',
  'love.joystickadded',
  'love.joystickaxis',
  'love.joystickhat',
  'love.joystickpressed',
  'love.joystickreleased',
  'love.joystickremoved',
  'love.keypressed',
  'love.keyreleased',
  'love.lowmemory',
  'love.mousefocus',
  'love.mousemoved',
  'love.mousepressed',
  'love.mousereleased',
  'love.textedited',
  'love.textinput',
  'love.touchmoved',
  'love.touchpressed',
  'love.touchreleased',
  'love.visible',
  'love.wheelmoved',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'love.thread',
  'love.thread.getChannel',
  'love.thread.newChannel',
  'love.thread.newThread',
  'Channel',
  'Channel:clear',
  'Channel:demand',
  'Channel:getCount',
  'Channel:hasRead',
  'Channel:peek',
  'Channel:performAtomic',
  'Channel:pop',
  'Channel:push',
  'Channel:supply',
  'Thread',
  'Thread:getError',
  'Thread:isRunning',
  'Thread:start',
  'Thread:wait',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

overrides.symbols['love.thread.newThread'] = overrides.symbols['love.thread.newThread'] or {}
merge_fields(overrides.symbols['love.thread.newThread'], {
  notes = 'Thread construction is implemented for LOVE-style code strings and filesystem-backed Lua chunks. Worker runtimes inherit the parent host bridge, share named channels, and currently execute asynchronously within the same Dart isolate.',
})

overrides.symbols['Thread:start'] = overrides.symbols['Thread:start'] or {}
merge_fields(overrides.symbols['Thread:start'], {
  notes = 'Starts an async worker runtime with LOVE-style vararg forwarding. Implemented payload support covers booleans, numbers, strings, Channel, Thread, and flat-table values compatible with the current marshalling layer.',
})

apply_symbol_overrides({
  'VideoStream:setSync',
  'VideoStream:getFilename',
  'VideoStream:isPlaying',
  'VideoStream:pause',
  'VideoStream:play',
  'VideoStream:rewind',
  'VideoStream:seek',
  'VideoStream:tell',
}, {
  status = 'implemented',
  conformance = 'smoke-tested',
})

apply_symbol_overrides({
  'love.video',
  'love.video.newVideoStream',
  'VideoStream',
}, {
  status = 'shimmed',
  conformance = 'smoke-tested',
})

overrides.symbols['love.video.newVideoStream'] =
  overrides.symbols['love.video.newVideoStream'] or {}
merge_fields(overrides.symbols['love.video.newVideoStream'], {
  notes = 'Constructs a control-layer VideoStream from LOVE-style filename or File inputs, reports `File is not open and cannot be opened` when those sources cannot be opened, and rejects non-Theora payloads up front. Playback control semantics are implemented, and Ogg Theora identification headers are parsed for metadata used by compatibility Video wrappers, including pixel dimensions, audio-track presence, and frame-rate hints used by the Flutter-backed video draw bridge.',
})

overrides.symbols['VideoStream'] = overrides.symbols['VideoStream'] or {}
merge_fields(overrides.symbols['VideoStream'], {
  notes = 'Control-layer VideoStream type with LOVE-style base-type hierarchy, including `typeOf("Stream")`, plus playback timing semantics and Source-backed or shared-stream sync control.',
})

return overrides
