local FIRST_CODEPOINT = 0x20
local LAST_CODEPOINT = 0x7e

local function write_or_fail(path, contents)
  local ok, message = love.filesystem.write(path, contents)
  if not ok then
    error("could not write " .. path .. ": " .. tostring(message))
  end
end

function love.load()
  local rasterizer = love.font.newTrueTypeRasterizer(12, "normal", 1)
  local font = love.graphics.newFont(rasterizer)
  local glyph_lines = {
    "# codepoint\twidth\theight\tadvance\tbearing_x\tbearing_y",
  }
  local kerning_lines = {
    "# left\tright\tkerning",
  }

  love.filesystem.createDirectory("glyphs")
  for codepoint = FIRST_CODEPOINT, LAST_CODEPOINT do
    local glyph = rasterizer:getGlyphData(codepoint)
    local width, height = glyph:getDimensions()
    local bearing_x, bearing_y = glyph:getBearing()
    glyph_lines[#glyph_lines + 1] = string.format(
      "%d\t%d\t%d\t%d\t%d\t%d",
      codepoint,
      width,
      height,
      glyph:getAdvance(),
      bearing_x,
      bearing_y
    )
    write_or_fail(string.format("glyphs/%03d.la8", codepoint), glyph:getString())
  end

  for left = FIRST_CODEPOINT, LAST_CODEPOINT do
    for right = FIRST_CODEPOINT, LAST_CODEPOINT do
      local kerning = font:getKerning(left, right)
      if kerning ~= 0 then
        kerning_lines[#kerning_lines + 1] = string.format(
          "%d\t%d\t%.17g",
          left,
          right,
          kerning
        )
      end
    end
  end

  write_or_fail("glyphs.tsv", table.concat(glyph_lines, "\n") .. "\n")
  write_or_fail("kerning.tsv", table.concat(kerning_lines, "\n") .. "\n")
  write_or_fail(
    "font.tsv",
    table.concat({
      "# size\tdpi_scale\thinting\theight\tascent\tdescent\tline_height",
      string.format(
        "12\t1\tnormal\t%d\t%d\t%d\t%d",
        rasterizer:getHeight(),
        rasterizer:getAscent(),
        rasterizer:getDescent(),
        rasterizer:getLineHeight()
      ),
      "",
    }, "\n")
  )

  print("native default font exported to " .. love.filesystem.getSaveDirectory())
  love.event.quit(0)
end
