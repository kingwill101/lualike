local ROOMS = require("src.room_catalog")

local VIEW_WIDTH = 320
local VIEW_HEIGHT = 180
local WORLD_WIDTH = ROOMS[1].worldWidth
local WORLD_HEIGHT = ROOMS[1].worldHeight
local TILE_SIZE = 16
local TILE_PITCH = 17
local SAVE_PATH = "relic_breach_save.lua"
local SOURCE_ASSET_ROOT = "assets/relic_breach/"
local MAX_ACTIVE_BOMBS = 18
local MAX_ACTIVE_PARTICLES = 12
local FAST_RENDER = os.getenv("LOVE2D_RELIC_FAST_RENDER") == "1"
local DISABLE_LIGHT_TEXTURES = os.getenv("LOVE2D_RELIC_DISABLE_LIGHT_TEXTURES") == "1"
local DRAW_DECORATIVE_BACKDROP = not FAST_RENDER
local DRAW_DECORATIVE_GLOWS = not FAST_RENDER and not DISABLE_LIGHT_TEXTURES
local DRAW_DECORATIVE_PROPS = not FAST_RENDER
local DRAW_DECORATIVE_WALL_TILES = not FAST_RENDER
local DRAW_FLOOR_DETAIL = not FAST_RENDER
local DRAW_HUD = true
local DRAW_MINIMAP = not FAST_RENDER
local DRAW_OBJECT_SPRITES = true
local DRAW_WATER_CAUSTICS = not FAST_RENDER and not DISABLE_LIGHT_TEXTURES

local ASSETS = {
  atlasRuntime = "art/kenney_roguelike_rpg_pack/Spritesheet/roguelikeSheet_runtime.png",
  atlas = "art/kenney_roguelike_rpg_pack/Spritesheet/roguelikeSheet_transparent.png",
  atlasMagenta = "art/kenney_roguelike_rpg_pack/Spritesheet/roguelikeSheet_magenta.png",
  characterAtlasRuntime = "art/kenney_roguelike_characters/Spritesheet/roguelikeChar_runtime.png",
  characterAtlas = "art/kenney_roguelike_characters/Spritesheet/roguelikeChar_transparent.png",
  characterAtlasMagenta = "art/kenney_roguelike_characters/Spritesheet/roguelikeChar_magenta.png",
  prompts = {
    bombClick = "art/kenney_input_prompts_pixel/Tiles/tile_0620.png",
    gamepadA = "art/kenney_input_prompts_pixel/Tiles/tile_0612.png",
    saveF5 = "art/kenney_input_prompts_pixel/Tiles/tile_0294.png",
  },
  lightConeRuntime = "art/kenney_light_masks/Default/cone_a_blur_runtime.png",
  lightCone = "art/kenney_light_masks/Default/cone_a_blur.png",
  lightCircleRuntime = "art/kenney_light_masks/Default/circle_a_streaks_runtime.png",
  lightCircle = "art/kenney_light_masks/Default/circle_a_streaks.png",
  waterCausticsRuntime = "art/kenney_light_masks/Default/water_caustics_a_runtime.png",
  waterCaustics = "art/kenney_light_masks/Default/water_caustics_a.png",
  fonts = {
    title = "fonts/kenney_fonts/Fonts/Kenney Rocket Square.ttf",
    body = "fonts/kenney_fonts/Fonts/Kenney Pixel.ttf",
  },
  sounds = {
    footsteps = {
      "audio/kenney_impact_sounds/Audio/footstep_concrete_000.ogg",
      "audio/kenney_impact_sounds/Audio/footstep_concrete_001.ogg",
      "audio/kenney_impact_sounds/Audio/footstep_concrete_002.ogg",
      "audio/kenney_impact_sounds/Audio/footstep_concrete_003.ogg",
      "audio/kenney_impact_sounds/Audio/footstep_concrete_004.ogg",
    },
    drop = {
      "audio/kenney_ui_audio/Audio/click3.ogg",
    },
    explode = {
      "audio/kenney_impact_sounds/Audio/impactWood_heavy_002.ogg",
      "audio/kenney_impact_sounds/Audio/impactWood_heavy_003.ogg",
    },
    breakCrate = {
      "audio/kenney_impact_sounds/Audio/impactWood_medium_001.ogg",
      "audio/kenney_impact_sounds/Audio/impactWood_medium_002.ogg",
    },
    save = {
      "audio/kenney_music_jingles/Audio/8-Bit jingles/jingles_NES07.ogg",
    },
    clear = {
      "audio/kenney_music_jingles/Audio/Hit jingles/jingles_HIT05.ogg",
    },
    reset = {
      "audio/kenney_ui_audio/Audio/click2.ogg",
    },
  },
}

local TILE = {
  floors = {
    { 21, 16 },
    { 22, 16 },
    { 23, 16 },
    { 24, 16 },
    { 25, 16 },
    { 22, 17 },
    { 23, 17 },
    { 24, 17 },
    { 25, 17 },
    { 31, 16 },
    { 32, 16 },
  },
  wallTop = {
    { 21, 14 },
    { 22, 14 },
    { 23, 14 },
    { 24, 14 },
    { 25, 14 },
    { 26, 14 },
    { 27, 14 },
    { 28, 14 },
  },
  wallSide = {
    { 23, 14 },
    { 24, 14 },
    { 25, 14 },
    { 26, 14 },
  },
  shelf = {
    { 42, 13 },
    { 43, 13 },
    { 44, 13 },
    { 45, 13 },
    { 46, 13 },
    { 47, 13 },
    { 48, 13 },
    { 49, 13 },
    { 50, 13 },
    { 51, 13 },
  },
  crate = { 40, 11 },
  bomb = { 44, 11 },
  player = {
    actorFrames = {
      { 1, 6 },
      { 2, 6 },
    },
    fallback = { 52, 7 },
  },
  relic = { 44, 12 },
  bannerLeft = { 50, 6 },
  bannerRight = { 52, 6 },
  door = { 35, 14 },
}

local game = {
  canvas = nil,
  palette = {
    bg = { 0.03, 0.05, 0.12, 1.0 },
    wall = { 0.10, 0.14, 0.22, 1.0 },
    floorA = { 0.08, 0.11, 0.17, 1.0 },
    floorB = { 0.06, 0.09, 0.15, 1.0 },
    accent = { 0.43, 0.88, 0.62, 1.0 },
    danger = { 0.98, 0.44, 0.29, 1.0 },
    gold = { 0.98, 0.79, 0.30, 1.0 },
    ui = { 0.82, 0.88, 0.96, 1.0 },
    water = { 0.17, 0.33, 0.61, 0.78 },
    waterEdge = { 0.72, 0.90, 1.00, 0.25 },
    dark = { 0.02, 0.03, 0.06, 0.84 },
  },
  camera = { x = WORLD_WIDTH / 2, y = WORLD_HEIGHT / 2, shake = 0 },
  pointer = { x = WORLD_WIDTH / 2, y = WORLD_HEIGHT / 2, active = false },
  touches = {},
  particles = {},
  bombs = {},
  crates = {},
  walls = {},
  waterPools = {},
  props = {},
  relic = nil,
  world = nil,
  player = nil,
  playerShape = nil,
  playerSurface = "stone",
  playerFacing = 0,
  atlas = nil,
  characterAtlas = nil,
  lightCone = nil,
  lightCircle = nil,
  waterCaustics = nil,
  lightMasksNeedAdditive = false,
  particleImage = nil,
  particleTemplate = nil,
  quads = {},
  promptIcons = {},
  fonts = {},
  sounds = {},
  assetWarnings = {},
  status = "Booting",
  lastContact = "none",
  roomName = ROOMS[1].name,
  currentRoomIndex = 1,
  roomClear = false,
  exitReady = false,
  score = 0,
  bestScore = 0,
  time = 0,
  flash = 0,
  stepTimer = 0,
  showDebug = false,
  totalCrates = 0,
}

local COLOR_WHITE = { 1, 1, 1, 1 }

local FLOOR_DRAW_OPTIONS = {
  color = COLOR_WHITE,
  fallbackWidth = TILE_SIZE,
  fallbackHeight = TILE_SIZE,
}

local PROMPT_CHIPS_KEYBOARD = {
  { label = "Move WASD" },
  { icon = "bombClick", label = "Bomb" },
  { label = "Space" },
  { icon = "saveF5", label = "Save" },
  { label = "Reset R" },
  { label = "Debug Tab" },
}

local PROMPT_CHIPS_GAMEPAD = {
  { label = "Move WASD / LS" },
  { icon = "bombClick", label = "Bomb" },
  { icon = "gamepadA", label = "Bomb" },
  { label = "Space" },
  { icon = "saveF5", label = "Save" },
  { label = "Reset R" },
  { label = "Debug Tab" },
}

local WORLD_DRAW_MARGIN = 48
local MAX_TILE_X = math.floor(WORLD_WIDTH / TILE_SIZE) - 1
local MAX_TILE_Y = math.floor(WORLD_HEIGHT / TILE_SIZE) - 1
local FLOOR_DETAIL_TILE_STEP = 4
local PROP_DRAW_RADIUS = 32
local RELIC_DRAW_RADIUS = 56
local BODY_DRAW_RADIUS = 32

local PROP_DRAW_OPTIONS = {
  originX = 8,
  originY = 8,
}

local RELIC_DRAW_OPTIONS = {
  originX = 8,
  originY = 8,
  color = game.palette.gold,
}

local WALL_SIDE_LEFT_OPTIONS = {
  rotation = -math.pi * 0.5,
  originX = 0,
  originY = 0,
}

local WALL_SIDE_RIGHT_OPTIONS = {
  rotation = math.pi * 0.5,
  originX = 0,
  originY = 16,
}

local CRATE_DRAW_OPTIONS = {
  rotation = 0,
  originX = 8,
  originY = 8,
}

local BOMB_DRAW_OPTIONS = {
  originX = 8,
  originY = 8,
  scaleX = 1,
  scaleY = 1,
}

local PLAYER_DRAW_OPTIONS = {
  image = nil,
  originX = 8,
  originY = 8,
  scaleX = 1,
  rotation = 0,
}

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function magnitude(x, y)
  return math.sqrt(x * x + y * y)
end

local function set_color(color)
  love.graphics.setColor(color[1], color[2], color[3], color[4] or 1.0)
end

local function draw_light_mask(image, x, y, rotation, scaleX, scaleY, originX, originY, color)
  if image == nil then
    return
  end

  if not game.lightMasksNeedAdditive then
    set_color(color or COLOR_WHITE)
    love.graphics.draw(image, x, y, rotation or 0, scaleX or 1, scaleY or scaleX or 1, originX or 0, originY or 0)
    return
  end

  local blendMode, blendAlphaMode = love.graphics.getBlendMode()
  love.graphics.setBlendMode("add", "alphamultiply")
  set_color(color or COLOR_WHITE)
  love.graphics.draw(image, x, y, rotation or 0, scaleX or 1, scaleY or scaleX or 1, originX or 0, originY or 0)
  love.graphics.setBlendMode(blendMode, blendAlphaMode)
end

local function screen_transform()
  local width, height = love.graphics.getDimensions()
  local scale = math.min(width / VIEW_WIDTH, height / VIEW_HEIGHT)
  local drawWidth = VIEW_WIDTH * scale
  local drawHeight = VIEW_HEIGHT * scale
  local offsetX = math.floor((width - drawWidth) / 2)
  local offsetY = math.floor((height - drawHeight) / 2)
  return scale, offsetX, offsetY
end

local function screen_to_world(x, y)
  local scale, offsetX, offsetY = screen_transform()
  local canvasX = (x - offsetX) / scale
  local canvasY = (y - offsetY) / scale
  local worldX = canvasX + game.camera.x - VIEW_WIDTH / 2
  local worldY = canvasY + game.camera.y - VIEW_HEIGHT / 2
  return clamp(worldX, 0, WORLD_WIDTH), clamp(worldY, 0, WORLD_HEIGHT)
end

local function update_pointer(screenX, screenY)
  game.pointer.x, game.pointer.y = screen_to_world(screenX, screenY)
  game.pointer.active = true
end

local function make_solid_image()
  local imageData = love.image.newImageData(4, 4)
  for y = 0, 3 do
    for x = 0, 3 do
      imageData:setPixel(x, y, 1, 1, 1, 1)
    end
  end
  local image = love.graphics.newImage(imageData)
  image:setFilter("nearest", "nearest")
  return image
end

local function make_tone(frequency, duration, volume)
  local sampleRate = 22050
  local sampleCount = math.floor(sampleRate * duration)
  local soundData = love.sound.newSoundData(sampleCount, sampleRate, 16, 1)
  for i = 0, sampleCount - 1 do
    local t = i / sampleRate
    local envelope = 1.0 - (i / sampleCount)
    local sample = math.sin(t * frequency * math.pi * 2.0)
    soundData:setSample(i, sample * volume * envelope)
  end
  return love.audio.newSource(soundData, "static")
end

local function asset_candidates(path)
  if path:match("^assets/") then
    return { path }
  end

  return {
    path,
    SOURCE_ASSET_ROOT .. path,
  }
end

local function try_new_filedata(path)
  for _, candidate in ipairs(asset_candidates(path)) do
    local ok, fileData = pcall(love.filesystem.newFileData, candidate)
    if ok and fileData then
      return fileData, candidate
    end

    local readOk, contents = pcall(love.filesystem.read, candidate)
    if readOk and contents then
      local name = candidate:match("[^/]+$") or "asset.bin"
      local inlineOk, inlineData = pcall(love.filesystem.newFileData, contents, name)
      if inlineOk and inlineData then
        return inlineData, candidate
      end
    end
  end

  return nil, nil
end

local function try_new_image(path)
  for _, candidate in ipairs(asset_candidates(path)) do
    local ok, image = pcall(love.graphics.newImage, candidate)
    if ok and image then
      image:setFilter("nearest", "nearest")
      return image, candidate
    end

    local imageDataOk, imageData = pcall(love.image.newImageData, candidate)
    if imageDataOk and imageData then
      local dataImageOk, dataImage = pcall(love.graphics.newImage, imageData)
      if dataImageOk and dataImage then
        dataImage:setFilter("nearest", "nearest")
        return dataImage, candidate
      end
    end
  end

  local fileData = try_new_filedata(path)
  if not fileData then
    return nil, nil
  end

  local ok, image = pcall(love.graphics.newImage, fileData)
  if ok and image then
    image:setFilter("nearest", "nearest")
    return image
  end

  local imageDataOk, imageData = pcall(love.image.newImageData, fileData)
  if not imageDataOk or not imageData then
    return nil, nil
  end

  local dataImageOk, dataImage = pcall(love.graphics.newImage, imageData)
  if not dataImageOk or not dataImage then
    return nil, nil
  end
  dataImage:setFilter("nearest", "nearest")
  return dataImage
end

local function try_new_font(path, size)
  for _, candidate in ipairs(asset_candidates(path)) do
    local ok, font = pcall(love.graphics.newFont, candidate, size)
    if ok and font then
      return font
    end
  end

  local fileData = try_new_filedata(path)
  if fileData then
    local fallbackOk, fallbackFont = pcall(love.graphics.newFont, fileData, size)
    if fallbackOk then
      return fallbackFont
    end
  end

  return love.graphics.newFont(size)
end

local function try_new_source(path)
  for _, candidate in ipairs(asset_candidates(path)) do
    local ok, source = pcall(love.audio.newSource, candidate, "static")
    if ok and source then
      return source
    end
  end

  local fileData = try_new_filedata(path)
  if fileData then
    local fallbackOk, fallbackSource = pcall(love.audio.newSource, fileData, "static")
    if fallbackOk then
      return fallbackSource
    end
  end

  return nil
end

local function load_sound_bank(paths, fallbackFactory)
  local sources = {}
  for _, path in ipairs(paths) do
    local source = try_new_source(path)
    if source then
      table.insert(sources, source)
    end
  end
  if #sources == 0 and fallbackFactory then
    table.insert(sources, fallbackFactory())
  end
  return sources
end

local function play_variant(sources, volume, pitchMin, pitchMax)
  if not sources or #sources == 0 then
    return
  end

  local index = love.math.random(1, #sources)
  local clone = sources[index]:clone()
  if volume then
    clone:setVolume(volume)
  end
  if pitchMin and pitchMax then
    clone:setPitch(lerp(pitchMin, pitchMax, love.math.random()))
  end
  clone:play()
end

local function tile_quad_for_image(image, col, row)
  if not image then
    return nil
  end
  local atlasWidth, atlasHeight = image:getDimensions()
  return love.graphics.newQuad(
    (col - 1) * TILE_PITCH,
    (row - 1) * TILE_PITCH,
    TILE_SIZE,
    TILE_SIZE,
    atlasWidth,
    atlasHeight
  )
end

local function tile_quad(col, row)
  return tile_quad_for_image(game.atlas, col, row)
end

local function load_tiles(tileList)
  local quads = {}
  for _, tile in ipairs(tileList) do
    local quad = tile_quad(tile[1], tile[2])
    if quad then
      table.insert(quads, quad)
    end
  end
  return quads
end

local function load_assets()
  game.atlas = try_new_image(ASSETS.atlasRuntime)
  if game.atlas == nil then
    game.atlas = try_new_image(ASSETS.atlas)
  end
  if game.atlas == nil then
    game.atlas = try_new_image(ASSETS.atlasMagenta)
  end
  game.characterAtlas = try_new_image(ASSETS.characterAtlasRuntime)
  if game.characterAtlas == nil then
    game.characterAtlas = try_new_image(ASSETS.characterAtlas)
  end
  if game.characterAtlas == nil then
    game.characterAtlas = try_new_image(ASSETS.characterAtlasMagenta)
  end
  if not DISABLE_LIGHT_TEXTURES then
    game.lightMasksNeedAdditive = false
    game.lightCone = try_new_image(ASSETS.lightConeRuntime)
    if game.lightCone == nil then
      game.lightCone = try_new_image(ASSETS.lightCone)
      game.lightMasksNeedAdditive = game.lightCone ~= nil
    end
    game.lightCircle = try_new_image(ASSETS.lightCircleRuntime)
    if game.lightCircle == nil then
      game.lightCircle = try_new_image(ASSETS.lightCircle)
      game.lightMasksNeedAdditive = game.lightMasksNeedAdditive or game.lightCircle ~= nil
    end
    game.waterCaustics = try_new_image(ASSETS.waterCausticsRuntime)
    if game.waterCaustics == nil then
      game.waterCaustics = try_new_image(ASSETS.waterCaustics)
      game.lightMasksNeedAdditive = game.lightMasksNeedAdditive or game.waterCaustics ~= nil
    end
  else
    game.lightMasksNeedAdditive = false
    game.lightCone = nil
    game.lightCircle = nil
    game.waterCaustics = nil
  end
  for name, path in pairs(ASSETS.prompts) do
    game.promptIcons[name] = try_new_image(path)
  end
  game.assetWarnings.atlas = game.atlas == nil
  game.assetWarnings.characterAtlas = game.characterAtlas == nil

  game.fonts.title = try_new_font(ASSETS.fonts.title, 8)
  game.fonts.body = try_new_font(ASSETS.fonts.body, 6)
  game.fonts.small = try_new_font(ASSETS.fonts.body, 5)

  game.quads.floors = load_tiles(TILE.floors)
  game.quads.wallTop = load_tiles(TILE.wallTop)
  game.quads.wallSide = load_tiles(TILE.wallSide)
  game.quads.shelf = load_tiles(TILE.shelf)
  game.quads.crate = tile_quad(TILE.crate[1], TILE.crate[2])
  game.quads.bomb = tile_quad(TILE.bomb[1], TILE.bomb[2])
  if game.characterAtlas then
    game.quads.playerFrames = {}
    for _, frame in ipairs(TILE.player.actorFrames) do
      local quad = tile_quad_for_image(game.characterAtlas, frame[1], frame[2])
      if quad then
        table.insert(game.quads.playerFrames, quad)
      end
    end
    game.quads.player = game.quads.playerFrames[1]
  else
    game.quads.player = tile_quad(TILE.player.fallback[1], TILE.player.fallback[2])
  end
  game.quads.relic = tile_quad(TILE.relic[1], TILE.relic[2])
  game.quads.bannerLeft = tile_quad(TILE.bannerLeft[1], TILE.bannerLeft[2])
  game.quads.bannerRight = tile_quad(TILE.bannerRight[1], TILE.bannerRight[2])
  game.quads.door = tile_quad(TILE.door[1], TILE.door[2])

  game.sounds.footsteps = load_sound_bank(ASSETS.sounds.footsteps, function()
    return make_tone(220, 0.05, 0.14)
  end)
  game.sounds.drop = load_sound_bank(ASSETS.sounds.drop, function()
    return make_tone(330, 0.08, 0.22)
  end)
  game.sounds.explode = load_sound_bank(ASSETS.sounds.explode, function()
    return make_tone(110, 0.22, 0.55)
  end)
  game.sounds.breakCrate = load_sound_bank(ASSETS.sounds.breakCrate, function()
    return make_tone(180, 0.12, 0.24)
  end)
  game.sounds.save = load_sound_bank(ASSETS.sounds.save, function()
    return make_tone(660, 0.12, 0.24)
  end)
  game.sounds.clear = load_sound_bank(ASSETS.sounds.clear, function()
    return make_tone(520, 0.16, 0.20)
  end)
  game.sounds.reset = load_sound_bank(ASSETS.sounds.reset, function()
    return make_tone(550, 0.08, 0.16)
  end)
end

local function prompt_chip_width(icon, label)
  local iconWidth = icon and 10 or 0
  local gapWidth = icon and 3 or 0
  return 6 + iconWidth + gapWidth + game.fonts.small:getWidth(label) + 6
end

local function draw_prompt_chip(x, y, icon, label)
  local chipHeight = 9
  local chipWidth = prompt_chip_width(icon, label)
  set_color({ 0.10, 0.14, 0.22, 0.94 })
  love.graphics.rectangle("fill", x, y, chipWidth, chipHeight, 5, 5)

  local textX = x + 4
  if icon then
    set_color({ 1, 1, 1, 1 })
    love.graphics.draw(icon, x + 4, y + 1, 0, 0.5, 0.5)
    textX = x + 17
  end

  set_color(game.palette.ui)
  love.graphics.print(label, textX, y + 2)
  return chipWidth
end

local function draw_prompt_row(x, y, chips)
  if chips == nil then
    return
  end
  local cursorX = x
  for _, chip in ipairs(chips) do
    local icon = chip.icon and game.promptIcons[chip.icon] or nil
    local chipWidth = draw_prompt_chip(cursorX, y, icon, chip.label)
    cursorX = cursorX + chipWidth + 4
  end
end

local function draw_quad(quad, x, y, options)
  local image = (options and options.image) or game.atlas
  if image and quad then
    local color = (options and options.color) or COLOR_WHITE
    set_color(color)
    love.graphics.draw(
      image,
      quad,
      x,
      y,
      (options and options.rotation) or 0,
      (options and options.scaleX) or 1,
      (options and options.scaleY) or (options and options.scaleX) or 1,
      (options and options.originX) or 0,
      (options and options.originY) or 0
    )
    return
  end

  local width = (options and options.fallbackWidth) or TILE_SIZE
  local height = (options and options.fallbackHeight) or TILE_SIZE
  set_color((options and options.color) or game.palette.ui)
  love.graphics.rectangle(
    "fill",
    x - ((options and options.originX) or 0),
    y - ((options and options.originY) or 0),
    width,
    height,
    2,
    2
  )
end

local function pick_floor_quad(tileX, tileY)
  local quads = game.quads.floors
  if #quads == 0 then
    return nil
  end
  local index = ((tileX * 7 + tileY * 11) % #quads) + 1
  return quads[index]
end

local function pick_wall_quad(index, list)
  if #list == 0 then
    return nil
  end
  return list[((index * 5) % #list) + 1]
end

local function cycle_quad(list, index)
  if #list == 0 then
    return nil
  end
  return list[((index - 1) % #list) + 1]
end

local function draw_backdrop_region(x, y, w, h)
  if w <= 0 or h <= 0 then
    return
  end

  set_color({ 0.04, 0.07, 0.13, 1.0 })
  love.graphics.rectangle("fill", x, y, w, h)

  if game.atlas then
    if not DRAW_DECORATIVE_BACKDROP then
      set_color({ 0.02, 0.03, 0.06, 0.32 })
      love.graphics.rectangle("fill", x, y, w, h)
      return
    end

    local tileScale = 2
    local tileStep = TILE_SIZE * tileScale
    local rowIndex = 1
    for drawY = y, y + h + tileStep, tileStep do
      local columnIndex = 1
      for drawX = x, x + w + tileStep, tileStep do
        local quadList = ((rowIndex + columnIndex) % 5 == 0) and game.quads.wallTop or game.quads.floors
        local quad = cycle_quad(quadList, rowIndex * 11 + columnIndex * 7)
        if quad then
          draw_quad(quad, drawX, drawY, {
            image = game.atlas,
            scaleX = tileScale,
            scaleY = tileScale,
            color = { 0.70, 0.79, 0.96, 0.14 },
          })
        end
        columnIndex = columnIndex + 1
      end
      rowIndex = rowIndex + 1
    end
  end

  if DRAW_WATER_CAUSTICS and game.waterCaustics then
    draw_light_mask(
      game.waterCaustics,
      x + w * 0.5,
      y + h * 0.5,
      game.time * 0.025,
      math.max(w / 512, 0.25),
      math.max(h / 512, 0.25),
      256,
      256,
      { 0.48, 0.70, 1.00, 0.12 }
    )
  end

  if DRAW_DECORATIVE_GLOWS and game.lightCircle then
    local glowColor = { game.palette.accent[1], game.palette.accent[2], game.palette.accent[3], 0.08 }
    draw_light_mask(game.lightCircle, x + w * 0.18, y + h * 0.52, 0, 0.10, 0.10, 256, 256, glowColor)
    draw_light_mask(game.lightCircle, x + w * 0.82, y + h * 0.48, 0, 0.08, 0.08, 256, 256, glowColor)
  end

  set_color({ 0.02, 0.03, 0.06, 0.32 })
  love.graphics.rectangle("fill", x, y, w, h)
end

local function draw_presentation_frame(scale, offsetX, offsetY)
  local width, height = love.graphics.getDimensions()
  local drawWidth = VIEW_WIDTH * scale
  local drawHeight = VIEW_HEIGHT * scale
  local canvasRight = offsetX + drawWidth
  local canvasBottom = offsetY + drawHeight

  draw_backdrop_region(0, 0, width, offsetY)
  draw_backdrop_region(0, canvasBottom, width, height - canvasBottom)
  draw_backdrop_region(0, offsetY, offsetX, drawHeight)
  draw_backdrop_region(canvasRight, offsetY, width - canvasRight, drawHeight)

  if game.atlas and game.quads.bannerLeft and game.quads.bannerRight and offsetY > 48 then
    set_color({ 1, 1, 1, 0.24 })
    love.graphics.draw(game.atlas, game.quads.bannerLeft, offsetX + 26, offsetY * 0.42, 0, 2.4, 2.4, 8, 8)
    love.graphics.draw(
      game.atlas,
      game.quads.bannerRight,
      width - offsetX - 26,
      offsetY * 0.42,
      0,
      2.4,
      2.4,
      8,
      8
    )
  end

  set_color({ 0.00, 0.02, 0.05, 0.72 })
  love.graphics.rectangle("line", offsetX - 4, offsetY - 4, drawWidth + 8, drawHeight + 8, 12, 12)
  set_color({ game.palette.accent[1], game.palette.accent[2], game.palette.accent[3], 0.22 })
  love.graphics.rectangle("line", offsetX - 2, offsetY - 2, drawWidth + 4, drawHeight + 4, 12, 12)
end

local function rect_contains(rect, x, y)
  return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function rect_intersects_bounds(x, y, w, h, left, top, right, bottom)
  return x < right and x + w > left and y < bottom and y + h > top
end

local function center_intersects_bounds(x, y, radius, left, top, right, bottom)
  return x + radius > left and x - radius < right and y + radius > top and y - radius < bottom
end

local function visible_tile_range(minWorld, maxWorld, minIndex, maxIndex)
  local startIndex = math.max(minIndex, math.floor(minWorld / TILE_SIZE))
  local endIndex = math.min(maxIndex, math.floor(maxWorld / TILE_SIZE))
  if startIndex > endIndex then
    return nil, nil
  end
  return startIndex, endIndex
end

local function align_tile_start(index, step)
  return math.ceil(index / step) * step
end

local function visible_world_bounds(margin)
  return game.camera.x - VIEW_WIDTH / 2 - margin,
    game.camera.y - VIEW_HEIGHT / 2 - margin,
    game.camera.x + VIEW_WIDTH / 2 + margin,
    game.camera.y + VIEW_HEIGHT / 2 + margin
end

local function current_room()
  return ROOMS[game.currentRoomIndex]
end

local function body_is_alive(body)
  return body ~= nil and not body:isDestroyed()
end

local function body_position(body)
  if not body_is_alive(body) then
    return nil, nil
  end
  return body:getPosition()
end

local function copy_rect(rect)
  return {
    x = rect.x,
    y = rect.y,
    w = rect.w,
    h = rect.h,
  }
end

local function copy_point(point)
  return {
    x = point.x,
    y = point.y,
  }
end

local function find_water_pool(x, y)
  for _, pool in ipairs(game.waterPools) do
    if rect_contains(pool, x, y) then
      return pool
    end
  end
  return nil
end

local function is_at_exit()
  local room = current_room()
  if not room.exit or not game.player then
    return false
  end

  local playerX, playerY = game.player:getPosition()
  local dx = playerX - room.exit.x
  local dy = playerY - room.exit.y
  return magnitude(dx, dy) <= (room.exit.radius or 20)
end

local function create_particle_system()
  local system = love.graphics.newParticleSystem(game.particleImage, 96)
  system:setParticleLifetime(0.20, 0.55)
  system:setLinearAcceleration(-36, -36, 36, 36)
  system:setSizes(1.0, 0.5, 0.0)
  system:setSpin(-4, 4)
  system:setSpeed(18, 78)
  system:setSpread(math.pi * 2)
  system:setColors(
    0.98, 0.79, 0.30, 1.0,
    0.98, 0.44, 0.29, 0.7,
    0.82, 0.88, 0.96, 0.0
  )
  return system
end

local function spawn_explosion(x, y, radius)
  local particleSystem = game.particleTemplate:clone()
  particleSystem:setPosition(x, y)
  particleSystem:emit(36)
  if #game.particles >= MAX_ACTIVE_PARTICLES then
    table.remove(game.particles, 1)
  end
  table.insert(game.particles, particleSystem)
  game.camera.shake = math.max(game.camera.shake, radius * 0.25)
  game.flash = 0.22
  play_variant(game.sounds.explode, 0.48, 0.96, 1.04)
end

local function save_progress()
  local payload = string.format(
    "bestScore=%d\nlastScore=%d\n",
    game.bestScore,
    game.score
  )
  love.filesystem.write(SAVE_PATH, payload)
  game.status = "Progress saved to " .. SAVE_PATH
  play_variant(game.sounds.save, 0.32)
end

local function load_progress()
  if not love.filesystem.getInfo(SAVE_PATH) then
    return
  end
  local content = love.filesystem.read(SAVE_PATH)
  local bestScore = tonumber(content:match("bestScore=(%d+)"))
  if bestScore then
    game.bestScore = bestScore
  end
end

local function spawn_crate(x, y)
  local body = love.physics.newBody(game.world, x, y, "dynamic")
  local shape = love.physics.newRectangleShape(12, 12)
  local fixture = love.physics.newFixture(body, shape, 0.7)
  fixture:setFriction(0.6)
  fixture:setUserData("crate")
  body:setLinearDamping(5)
  body:setAngularDamping(8)
  body:setUserData("crate")
  local crate = {
    body = body,
    shape = shape,
    fixture = fixture,
    destroyed = false,
  }
  table.insert(game.crates, crate)
  return crate
end

local function build_room()
  local room = current_room()
  game.walls = {}
  game.props = {}
  game.waterPools = {}
  for _, pool in ipairs(room.waterPools) do
    table.insert(game.waterPools, copy_rect(pool))
  end
  game.relic = copy_point(room.relic)

  for _, wall in ipairs(room.walls) do
    local body = love.physics.newBody(game.world, wall.x, wall.y, "static")
    local shape = love.physics.newRectangleShape(wall.w, wall.h)
    local fixture = love.physics.newFixture(body, shape)
    fixture:setUserData("wall")
    body:setUserData("wall")
    table.insert(game.walls, {
      body = body,
      shape = shape,
      fixture = fixture,
      w = wall.w,
      h = wall.h,
    })
  end

  for _, prop in ipairs(room.props) do
    local quad = nil
    if prop.kind == "shelf" then
      quad = cycle_quad(game.quads.shelf, prop.variant or 1)
    elseif prop.kind == "banner" then
      quad = prop.variant == "right" and game.quads.bannerRight or game.quads.bannerLeft
    elseif prop.kind == "door" then
      quad = game.quads.door
    end

    table.insert(game.props, {
      kind = prop.kind,
      x = prop.x,
      y = prop.y,
      role = prop.role,
      quad = quad,
    })
  end

  game.crates = {}
  for _, position in ipairs(room.crates) do
    spawn_crate(position.x, position.y)
  end
  game.totalCrates = #game.crates
end

local function create_player()
  local room = current_room()
  local body = love.physics.newBody(game.world, room.playerSpawn.x, room.playerSpawn.y, "dynamic")
  local shape = love.physics.newCircleShape(6)
  local fixture = love.physics.newFixture(body, shape, 1.0)
  fixture:setFriction(0.2)
  fixture:setUserData("player")
  body:setLinearDamping(10)
  body:setUserData("player")
  game.player = body
  game.playerShape = shape
end

local function reset_world(preserveRun)
  local room = current_room()
  game.time = 0
  if not preserveRun then
    game.score = 0
  end
  game.lastContact = "none"
  game.roomName = room.name
  game.roomClear = false
  game.exitReady = false
  game.flash = 0
  game.camera.shake = 0
  game.pointer.active = false
  game.playerFacing = 0
  game.playerSurface = "stone"
  game.particles = {}
  game.bombs = {}
  game.stepTimer = 0
  game.world = love.physics.newWorld(0, 0, true)
  game.world:setCallbacks(function()
    game.lastContact = "impact"
  end)
  build_room()
  create_player()
  game.status = "Entered " .. room.name
  game.camera.x = room.worldWidth / 2
  game.camera.y = room.worldHeight / 2
  play_variant(game.sounds.reset, 0.18)
end

local function advance_room()
  game.currentRoomIndex = (game.currentRoomIndex % #ROOMS) + 1
  reset_world(true)
  game.status = "Transitioned to " .. current_room().name
end

local function detonate_bomb(index)
  local bomb = game.bombs[index]
  if not bomb then
    return
  end

  local x, y = body_position(bomb.body)
  if x == nil or y == nil then
    table.remove(game.bombs, index)
    return
  end
  local radius = 54
  bomb.body:destroy()
  bomb.body = nil

  local destroyedCrates = 0
  for crateIndex = #game.crates, 1, -1 do
    local crate = game.crates[crateIndex]
    if not crate.destroyed and body_is_alive(crate.body) then
      local cx, cy = crate.body:getPosition()
      local dx = cx - x
      local dy = cy - y
      local distance = math.sqrt(dx * dx + dy * dy)
      if distance < radius then
        local force = (radius - distance) * 3.0
        local nx = dx / math.max(distance, 0.01)
        local ny = dy / math.max(distance, 0.01)
        if body_is_alive(crate.body) then
          crate.body:applyLinearImpulse(nx * force, ny * force)
        end
        if distance < radius * 0.72 and body_is_alive(crate.body) then
          crate.destroyed = true
          crate.body:destroy()
          crate.body = nil
          table.remove(game.crates, crateIndex)
          destroyedCrates = destroyedCrates + 1
        end
      end
    end
  end

  local px, py = game.player:getPosition()
  local pdx = px - x
  local pdy = py - y
  local playerDistance = math.sqrt(pdx * pdx + pdy * pdy)
  if playerDistance < radius then
    local playerForce = (radius - playerDistance) * 4.0
    local nx = pdx / math.max(playerDistance, 0.01)
    local ny = pdy / math.max(playerDistance, 0.01)
    game.player:applyLinearImpulse(nx * playerForce, ny * playerForce)
  end

  spawn_explosion(x, y, radius)
  if destroyedCrates > 0 then
    game.score = game.score + destroyedCrates
    game.bestScore = math.max(game.bestScore, game.score)
    play_variant(game.sounds.breakCrate, 0.42, 0.96, 1.06)
    if #game.crates == 0 then
      game.roomClear = true
      game.status = "Room clear. Reach the glowing exit."
      play_variant(game.sounds.clear, 0.32)
    else
      game.status = string.format("Blast cleared %d crate(s)", destroyedCrates)
    end
  else
    game.status = "Blast missed the crate stack"
  end

  table.remove(game.bombs, index)
end

local function drop_bomb(x, y)
  if #game.bombs >= MAX_ACTIVE_BOMBS then
    game.status = string.format("Bomb rack full (%d max)", MAX_ACTIVE_BOMBS)
    return
  end

  local body = love.physics.newBody(game.world, x, y, "dynamic")
  local shape = love.physics.newCircleShape(4)
  local fixture = love.physics.newFixture(body, shape, 0.2)
  fixture:setRestitution(0.2)
  fixture:setUserData("bomb")
  body:setLinearDamping(4)
  body:setUserData("bomb")
  table.insert(game.bombs, {
    body = body,
    shape = shape,
    fuse = 1.4,
  })
  game.status = "Bomb armed"
  play_variant(game.sounds.drop, 0.24, 0.96, 1.04)
end

local function aim_position()
  if game.pointer.active then
    return game.pointer.x, game.pointer.y
  end
  return game.player:getPosition()
end

local function update_player_velocity()
  local moveX = 0
  local moveY = 0
  if love.keyboard.isDown("a", "left") then
    moveX = moveX - 1
  end
  if love.keyboard.isDown("d", "right") then
    moveX = moveX + 1
  end
  if love.keyboard.isDown("w", "up") then
    moveY = moveY - 1
  end
  if love.keyboard.isDown("s", "down") then
    moveY = moveY + 1
  end

  local joysticks = love.joystick.getJoysticks()
  local pad = joysticks[1]
  if pad and pad:isGamepad() then
    local axisX = pad:getGamepadAxis("leftx")
    local axisY = pad:getGamepadAxis("lefty")
    if math.abs(axisX) > 0.18 then
      moveX = axisX
    end
    if math.abs(axisY) > 0.18 then
      moveY = axisY
    end
  end

  local length = magnitude(moveX, moveY)
  if length > 0 then
    moveX = moveX / length
    moveY = moveY / length
  end

  local playerX, playerY = game.player:getPosition()
  local pool = find_water_pool(playerX, playerY)
  local speed = pool and 58 or 92
  game.playerSurface = pool and "water" or "stone"
  if length > 0 then
    game.playerFacing = math.atan(moveY, moveX) + math.pi * 0.5
  elseif game.pointer.active then
    local aimX, aimY = aim_position()
    game.playerFacing = math.atan(aimY - playerY, aimX - playerX) + math.pi * 0.5
  end

  game.player:setLinearVelocity(moveX * speed, moveY * speed)
end

local function draw_floor(left, top, right, bottom)
  local floorX = clamp(left, 0, WORLD_WIDTH)
  local floorY = clamp(top, 0, WORLD_HEIGHT)
  local floorRight = clamp(right, 0, WORLD_WIDTH)
  local floorBottom = clamp(bottom, 0, WORLD_HEIGHT)
  local floorW = floorRight - floorX
  local floorH = floorBottom - floorY
  if floorW <= 0 or floorH <= 0 then
    return
  end

  set_color(game.palette.floorA)
  love.graphics.rectangle("fill", floorX, floorY, floorW, floorH)

  local startTileX, endTileX = visible_tile_range(left, right, 0, MAX_TILE_X)
  local startTileY, endTileY = visible_tile_range(top, bottom, 0, MAX_TILE_Y)
  if startTileX == nil or startTileY == nil then
    return
  end
  if not DRAW_FLOOR_DETAIL then
    return
  end

  local firstDetailTileX = align_tile_start(startTileX, FLOOR_DETAIL_TILE_STEP)
  local firstDetailTileY = align_tile_start(startTileY, FLOOR_DETAIL_TILE_STEP)
  for tileY = firstDetailTileY, endTileY, FLOOR_DETAIL_TILE_STEP do
    for tileX = firstDetailTileX, endTileX, FLOOR_DETAIL_TILE_STEP do
      local x = tileX * TILE_SIZE
      local y = tileY * TILE_SIZE
      local quad = pick_floor_quad(tileX, tileY)
      draw_quad(quad, x, y, FLOOR_DRAW_OPTIONS)
    end
  end
end

local function draw_water(left, top, right, bottom)
  for _, pool in ipairs(game.waterPools) do
    if rect_intersects_bounds(pool.x, pool.y, pool.w, pool.h, left, top, right, bottom) then
      set_color(game.palette.water)
      love.graphics.rectangle("fill", pool.x, pool.y, pool.w, pool.h, 6, 6)
      if DRAW_WATER_CAUSTICS and game.waterCaustics then
        local scaleX = pool.w / 512
        local scaleY = pool.h / 512
        draw_light_mask(
          game.waterCaustics,
          pool.x + math.sin(game.time * 0.7) * 5,
          pool.y + math.cos(game.time * 0.5) * 4,
          0,
          scaleX,
          scaleY,
          nil,
          nil,
          { 0.78, 0.96, 1.00, 0.18 }
        )
        draw_light_mask(
          game.waterCaustics,
          pool.x - math.cos(game.time * 0.6) * 4,
          pool.y + math.sin(game.time * 0.8) * 5,
          0,
          scaleX,
          scaleY,
          nil,
          nil,
          { 0.36, 0.74, 1.00, 0.22 }
        )
      end
      set_color(game.palette.waterEdge)
      love.graphics.rectangle("line", pool.x, pool.y, pool.w, pool.h, 6, 6)
    end
  end
end

local function draw_walls(left, top, right, bottom)
  set_color(game.palette.wall)
  for _, wall in ipairs(game.walls) do
    local x, y = wall.body:getPosition()
    local wallX = x - wall.w / 2
    local wallY = y - wall.h / 2
    if rect_intersects_bounds(wallX, wallY, wall.w, wall.h, left, top, right, bottom) then
      love.graphics.rectangle("fill", wallX, wallY, wall.w, wall.h)
    end
  end

  local startColumn, endColumn = visible_tile_range(left, right, 1, MAX_TILE_X - 1)
  if DRAW_DECORATIVE_WALL_TILES and startColumn ~= nil then
    if rect_intersects_bounds(0, 0, WORLD_WIDTH, 32, left, top, right, bottom) then
      for column = startColumn, endColumn do
        local x = column * TILE_SIZE
        local topQuad = pick_wall_quad(column, game.quads.wallTop)
        draw_quad(topQuad, x, 8)
      end
    end

    if rect_intersects_bounds(0, WORLD_HEIGHT - 32, WORLD_WIDTH, 32, left, top, right, bottom) then
      for column = startColumn, endColumn do
        local x = column * TILE_SIZE
        local bottomQuad = pick_wall_quad(column + 3, game.quads.wallTop)
        draw_quad(bottomQuad, x, WORLD_HEIGHT - 24)
      end
    end
  end

  local startRow, endRow = visible_tile_range(top, bottom, 1, MAX_TILE_Y - 1)
  if DRAW_DECORATIVE_WALL_TILES and startRow ~= nil then
    local drawLeftSide = rect_intersects_bounds(0, 0, 32, WORLD_HEIGHT, left, top, right, bottom)
    local drawRightSide = rect_intersects_bounds(WORLD_WIDTH - 32, 0, 32, WORLD_HEIGHT, left, top, right, bottom)
    if drawLeftSide or drawRightSide then
      for row = startRow, endRow do
        local y = row * TILE_SIZE
        if drawLeftSide then
          local leftQuad = pick_wall_quad(row, game.quads.wallSide)
          draw_quad(leftQuad, 8, y, WALL_SIDE_LEFT_OPTIONS)
        end
        if drawRightSide then
          local rightQuad = pick_wall_quad(row + 2, game.quads.wallSide)
          draw_quad(rightQuad, WORLD_WIDTH - 8, y, WALL_SIDE_RIGHT_OPTIONS)
        end
      end
    end
  end
end

local function draw_props(left, top, right, bottom)
  for _, prop in ipairs(game.props) do
    if center_intersects_bounds(prop.x, prop.y, PROP_DRAW_RADIUS, left, top, right, bottom) then
      if DRAW_DECORATIVE_GLOWS and prop.kind == "door" and prop.role == "exit" and game.roomClear and game.lightCircle then
        local pulse = 0.05 + math.sin(game.time * 4.0) * 0.008
        draw_light_mask(game.lightCircle, prop.x, prop.y, 0, pulse, pulse, 256, 256, { 1.00, 0.90, 0.36, 0.20 })
      end
      if prop.kind == "shelf" and DRAW_DECORATIVE_PROPS then
        draw_quad(prop.quad, prop.x, prop.y, PROP_DRAW_OPTIONS)
      elseif prop.kind == "banner" and DRAW_DECORATIVE_PROPS then
        draw_quad(prop.quad, prop.x, prop.y, PROP_DRAW_OPTIONS)
      elseif prop.kind == "door" then
        draw_quad(prop.quad, prop.x, prop.y, PROP_DRAW_OPTIONS)
      end
    end
  end

  if game.relic and center_intersects_bounds(game.relic.x, game.relic.y, RELIC_DRAW_RADIUS, left, top, right, bottom) then
    local bob = math.sin(game.time * 2.0) * 2.5
    if DRAW_DECORATIVE_GLOWS and game.lightCircle then
      draw_light_mask(
        game.lightCircle,
        game.relic.x,
        game.relic.y + 3,
        0,
        0.08,
        0.08,
        256,
        256,
        { 1.00, 0.82, 0.30, 0.18 }
      )
    end
    draw_quad(game.quads.relic, game.relic.x, game.relic.y + bob, RELIC_DRAW_OPTIONS)
  end
end

local function draw_crates(left, top, right, bottom)
  if not DRAW_OBJECT_SPRITES then
    set_color(game.palette.gold)
  end
  for _, crate in ipairs(game.crates) do
    local x, y = body_position(crate.body)
    if x ~= nil and y ~= nil and center_intersects_bounds(x, y, BODY_DRAW_RADIUS, left, top, right, bottom) then
      if DRAW_DECORATIVE_GLOWS and game.lightCircle then
        draw_light_mask(game.lightCircle, x, y + 2, 0, 0.04, 0.04, 256, 256, { 1.00, 0.76, 0.28, 0.08 })
      end
      if DRAW_OBJECT_SPRITES then
        CRATE_DRAW_OPTIONS.rotation = crate.body:getAngle()
        draw_quad(game.quads.crate, x, y, CRATE_DRAW_OPTIONS)
      else
        love.graphics.rectangle("fill", x - 6, y - 6, 12, 12, 2, 2)
      end
    end
  end
end

local function draw_bombs(left, top, right, bottom)
  for _, bomb in ipairs(game.bombs) do
    local x, y = body_position(bomb.body)
    if x ~= nil and y ~= nil and center_intersects_bounds(x, y, BODY_DRAW_RADIUS, left, top, right, bottom) then
      local pulse = 1.0 + math.sin(bomb.fuse * 12) * 0.08
      if DRAW_DECORATIVE_GLOWS and game.lightCircle then
        draw_light_mask(game.lightCircle, x, y, 0, 0.03 * pulse, 0.03 * pulse, 256, 256, { game.palette.danger[1], game.palette.danger[2], game.palette.danger[3], 0.18 })
      end
      if DRAW_OBJECT_SPRITES then
        BOMB_DRAW_OPTIONS.scaleX = pulse
        BOMB_DRAW_OPTIONS.scaleY = pulse
        draw_quad(game.quads.bomb, x, y, BOMB_DRAW_OPTIONS)
      else
        set_color(game.palette.danger)
        love.graphics.circle("fill", x, y, 4 * pulse)
      end
      love.graphics.push()
      love.graphics.translate(x, y - 4 * pulse)
      love.graphics.rotate(math.sin(game.time * 10.0 + x * 0.05) * 0.22)
      set_color({ 0.92, 0.74, 0.30, 1.0 })
      love.graphics.rectangle("fill", -0.5, -4, 1, 4)
      set_color({ 1.00, 0.90, 0.36, 0.95 })
      love.graphics.circle("fill", 0, -5, 1.5)
      love.graphics.pop()
    end
  end
end

local function draw_player()
  local x, y = game.player:getPosition()
  local vx, vy = game.player:getLinearVelocity()
  local moving = magnitude(vx, vy) > 12
  local facingScale = math.cos(game.playerFacing) < 0 and -1 or 1
  local bob = moving and math.sin(game.time * 14.0) * 0.7 or 0
  local playerQuad = game.quads.player

  if game.quads.playerFrames and #game.quads.playerFrames > 0 then
    local frameIndex = 1
    if moving and #game.quads.playerFrames > 1 then
      frameIndex = (math.floor(game.time * 10.0) % #game.quads.playerFrames) + 1
    end
    playerQuad = game.quads.playerFrames[frameIndex]
  end

  if DRAW_DECORATIVE_GLOWS and game.lightCircle then
    draw_light_mask(game.lightCircle, x, y + 1, 0, 0.045, 0.045, 256, 256, { game.palette.accent[1], game.palette.accent[2], game.palette.accent[3], 0.14 })
  end

  if DRAW_DECORATIVE_GLOWS and game.pointer.active and game.lightCone then
    local aimX, aimY = aim_position()
    local angle = math.atan(aimY - y, aimX - x) + math.pi * 0.5
    draw_light_mask(game.lightCone, x, y, angle, 0.18, 0.18, 256, 440, { 0.68, 0.90, 1.00, 0.14 })
  end

  set_color({ 0.01, 0.02, 0.05, 0.45 })
  love.graphics.ellipse("fill", x, y + 4, moving and 5.5 or 5, moving and 2.5 or 3)

  PLAYER_DRAW_OPTIONS.image = game.characterAtlas or game.atlas
  PLAYER_DRAW_OPTIONS.scaleX = facingScale
  PLAYER_DRAW_OPTIONS.rotation = moving and math.sin(game.time * 14.0) * 0.02 or 0
  draw_quad(playerQuad, x, y + bob, PLAYER_DRAW_OPTIONS)
end

local function draw_pointer(left, top, right, bottom)
  if not game.pointer.active then
    return
  end
  if not center_intersects_bounds(game.pointer.x, game.pointer.y, 8, left, top, right, bottom) then
    return
  end
  set_color(game.palette.accent)
  love.graphics.circle("line", game.pointer.x, game.pointer.y, 6)
  love.graphics.line(game.pointer.x - 8, game.pointer.y, game.pointer.x + 8, game.pointer.y)
  love.graphics.line(game.pointer.x, game.pointer.y - 8, game.pointer.x, game.pointer.y + 8)
end

local function draw_world()
  local left, top, right, bottom = visible_world_bounds(WORLD_DRAW_MARGIN)
  draw_floor(left, top, right, bottom)
  draw_water(left, top, right, bottom)
  draw_walls(left, top, right, bottom)
  draw_props(left, top, right, bottom)
  draw_crates(left, top, right, bottom)
  draw_bombs(left, top, right, bottom)

  set_color(game.palette.accent)
  for _, system in ipairs(game.particles) do
    love.graphics.draw(system)
  end

  draw_player()
  draw_pointer(left, top, right, bottom)
end

local function draw_minimap(x, y, w, h)
  set_color({ 0.02, 0.03, 0.06, 0.84 })
  love.graphics.rectangle("fill", x - 4, y - 4, w + 8, h + 8, 6, 6)
  set_color(game.palette.wall)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)

  local scaleX = w / WORLD_WIDTH
  local scaleY = h / WORLD_HEIGHT

  set_color({ 0.17, 0.33, 0.61, 0.85 })
  for _, pool in ipairs(game.waterPools) do
    love.graphics.rectangle("fill", x + pool.x * scaleX, y + pool.y * scaleY, pool.w * scaleX, pool.h * scaleY)
  end

  set_color(game.palette.gold)
  for _, crate in ipairs(game.crates) do
    local crateX, crateY = body_position(crate.body)
    if crateX ~= nil and crateY ~= nil then
      love.graphics.rectangle("fill", x + crateX * scaleX, y + crateY * scaleY, 2, 2)
    end
  end

  set_color(game.palette.danger)
  for _, bomb in ipairs(game.bombs) do
    local bombX, bombY = body_position(bomb.body)
    if bombX ~= nil and bombY ~= nil then
      love.graphics.rectangle("fill", x + bombX * scaleX, y + bombY * scaleY, 2, 2)
    end
  end

  if game.relic then
    set_color({ 1.0, 0.90, 0.36, 1.0 })
    love.graphics.rectangle("fill", x + game.relic.x * scaleX, y + game.relic.y * scaleY, 2, 2)
  end

  if game.roomClear then
    local room = current_room()
    set_color({ 1.00, 0.90, 0.36, 1.0 })
    love.graphics.rectangle("fill", x + room.exit.x * scaleX, y + room.exit.y * scaleY, 2, 2)
  end

  local playerX, playerY = game.player:getPosition()
  set_color(game.palette.accent)
  love.graphics.circle("fill", x + playerX * scaleX, y + playerY * scaleY, 2)
end

local function draw_hud()
  local width = VIEW_WIDTH
  local height = VIEW_HEIGHT
  local joysticks = love.joystick.getJoysticks()
  local hasGamepad = joysticks[1] and joysticks[1]:isGamepad()
  local brandText = "RELIC BREACH"
  local roomText = string.upper(game.roomName)
  local scoreText = "S" .. game.score .. "  B" .. game.bestScore
  local roomProgressText = "R" .. game.currentRoomIndex .. "/" .. #ROOMS
  local crateText = "C" .. #game.crates .. "/" .. game.totalCrates

  love.graphics.setFont(game.fonts.title)
  local cardWidth = math.max(
    72,
    game.fonts.title:getWidth(brandText) + 12,
    game.fonts.body:getWidth(roomText) + 12,
    game.fonts.small:getWidth(scoreText .. "  " .. roomProgressText .. "  " .. crateText) + 12
  )
  set_color({ 0.02, 0.03, 0.06, 0.72 })
  love.graphics.rectangle("fill", 8, 8, cardWidth, 28, 8, 8)
  set_color(game.palette.ui)
  love.graphics.print(brandText, 14, 12)

  love.graphics.setFont(game.fonts.body)
  love.graphics.print(roomText, 14, 20)

  love.graphics.setFont(game.fonts.small)
  set_color({ 0.74, 0.80, 0.90, 1.0 })
  love.graphics.print(scoreText, 14, 29)
  love.graphics.print(roomProgressText, 56, 29)
  love.graphics.print(crateText, 84, 29)

  if DRAW_MINIMAP then
    draw_minimap(width - 58, 8, 48, 28)
  end

  local statusText = game.status
  if game.assetWarnings.atlas then
    statusText = "Atlas failed to load. Fallback tiles are active."
  elseif game.assetWarnings.characterAtlas then
    statusText = "Character atlas failed to load. Using fallback actor tile."
  elseif game.roomClear then
    if game.exitReady then
      statusText = "Exit ready. Press Enter, E, or gamepad X."
    else
      statusText = "Room clear. Reach the glowing exit."
    end
  end

  local statusWidth = width - 20
  set_color({ 0.02, 0.03, 0.06, 0.76 })
  love.graphics.rectangle("fill", 10, height - 36, statusWidth, 10, 7, 7)
  set_color(game.palette.ui)
  love.graphics.printf(statusText, 15, height - 34, statusWidth - 10)

  if not game.showDebug then
    return
  end

  local promptChips = hasGamepad and PROMPT_CHIPS_GAMEPAD or PROMPT_CHIPS_KEYBOARD

  set_color({ 0.02, 0.03, 0.06, 0.76 })
  love.graphics.rectangle("fill", 10, height - 22, width - 20, 10, 7, 7)
  draw_prompt_row(14, height - 21, promptChips)
end

function love.load()
  love.math.setRandomSeed(os.time())
  love.graphics.setBackgroundColor(game.palette.bg)
  love.graphics.setDefaultFilter("nearest", "nearest")
  load_assets()
  game.particleImage = make_solid_image()
  game.particleTemplate = create_particle_system()
  love.graphics.setFont(game.fonts.body)
  load_progress()
  reset_world(false)
end

function love.update(dt)
  game.time = game.time + dt
  game.flash = math.max(0, game.flash - dt)
  game.camera.shake = math.max(0, game.camera.shake - dt * 36)

  update_player_velocity()
  game.world:update(dt)

  for index = #game.bombs, 1, -1 do
    local bomb = game.bombs[index]
    bomb.fuse = bomb.fuse - dt
    if bomb.fuse <= 0 then
      detonate_bomb(index)
    end
  end

  for index = #game.particles, 1, -1 do
    local system = game.particles[index]
    system:update(dt)
    if system:getCount() == 0 then
      table.remove(game.particles, index)
    end
  end

  local playerX, playerY = game.player:getPosition()
  game.exitReady = game.roomClear and is_at_exit()
  local vx, vy = game.player:getLinearVelocity()
  local playerSpeed = magnitude(vx, vy)
  if playerSpeed > 18 then
    game.stepTimer = game.stepTimer - dt
    if game.stepTimer <= 0 then
      play_variant(game.sounds.footsteps, game.playerSurface == "water" and 0.05 or 0.12, 0.96, 1.04)
      game.stepTimer = game.playerSurface == "water" and 0.34 or 0.24
    end
  else
    game.stepTimer = 0
  end

  game.camera.x = lerp(game.camera.x, playerX, math.min(1.0, dt * 8.0))
  game.camera.y = lerp(game.camera.y, playerY, math.min(1.0, dt * 8.0))
end

function love.draw()
  love.graphics.clear(game.palette.bg)

  local scale, offsetX, offsetY = screen_transform()
  local drawWidth = VIEW_WIDTH * scale
  local drawHeight = VIEW_HEIGHT * scale
  draw_presentation_frame(scale, offsetX, offsetY)

  local shakeX = love.math.random() * game.camera.shake - game.camera.shake * 0.5
  local shakeY = love.math.random() * game.camera.shake - game.camera.shake * 0.5

  love.graphics.setScissor(offsetX, offsetY, drawWidth, drawHeight)
  love.graphics.push()
  love.graphics.translate(offsetX, offsetY)
  love.graphics.scale(scale, scale)
  love.graphics.push()
  love.graphics.translate(
    math.floor(VIEW_WIDTH / 2 - game.camera.x + shakeX),
    math.floor(VIEW_HEIGHT / 2 - game.camera.y + shakeY)
  )
  draw_world()
  love.graphics.pop()

  if DRAW_HUD then
    draw_hud()
  end

  if game.flash > 0 then
    set_color({ 1.0, 0.95, 0.75, game.flash })
    love.graphics.rectangle("fill", 0, 0, VIEW_WIDTH, VIEW_HEIGHT)
  end
  love.graphics.pop()
  love.graphics.setScissor()
end

function love.keypressed(key)
  if key == "space" then
    local x, y = aim_position()
    drop_bomb(x, y)
  elseif key == "return" or key == "e" then
    if game.exitReady then
      advance_room()
    end
  elseif key == "f5" then
    save_progress()
  elseif key == "r" then
    game.currentRoomIndex = 1
    reset_world(false)
  elseif key == "tab" then
    game.showDebug = not game.showDebug
  end
end

function love.mousepressed(x, y, button)
  update_pointer(x, y)
  if button == 1 then
    local worldX, worldY = screen_to_world(x, y)
    drop_bomb(worldX, worldY)
  end
end

function love.mousemoved(x, y)
  update_pointer(x, y)
end

function love.touchpressed(id, x, y)
  game.touches[id] = true
  update_pointer(x, y)
  local worldX, worldY = screen_to_world(x, y)
  drop_bomb(worldX, worldY)
end

function love.touchmoved(id, x, y)
  if game.touches[id] then
    update_pointer(x, y)
  end
end

function love.touchreleased(id)
  game.touches[id] = nil
end

function love.gamepadpressed(_, button)
  if button == "a" then
    local x, y = game.player:getPosition()
    drop_bomb(x, y)
  elseif button == "x" and game.exitReady then
    advance_room()
  end
end
