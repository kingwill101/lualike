local ShaderCatalog = {
  {
    id = "solid",
    title = "Solid Color",
    file = "solid.frag",
    note = "uColor driven by animated hue",
  },
  {
    id = "gradient",
    title = "Gradient",
    file = "gradient.frag",
    note = "Static flutter brand gradient",
  },
  {
    id = "laser",
    title = "Laser",
    file = "laser.frag",
    note = "Animated line beam",
  },
  {
    id = "water",
    title = "Water",
    file = "water.frag",
    note = "Raymarched seascape",
  },
  {
    id = "jam",
    title = "Jam",
    file = "jam.glsl",
    note = "Procedural synth panel",
  },
  {
    id = "stars",
    title = "Stars",
    file = "stars.glsl",
    note = "Mouse-adjusted volumetric field",
  },
  {
    id = "snow",
    title = "Snow",
    file = "snow.glsl",
    note = "Layered snow on top of base texture",
    usesInputTexture = true,
  },
  {
    id = "glitch",
    title = "Glitch",
    file = "glitch.glsl",
    note = "RGB split + scanline effect",
    usesInputTexture = true,
  },
  {
    id = "pixelate",
    title = "Pixelate",
    file = "pixelation.frag",
    note = "Pixel blocks over source texture",
    usesInputTexture = true,
  },
  {
    id = "lava",
    title = "Lava",
    file = "lava.frag",
    note = "Classic flowing lava lamp",
  },
  {
    id = "barrel_blur",
    title = "Barrel Blur",
    file = "barrel_blur.glsl",
    note = "Distortion blend over source texture",
    usesInputTexture = true,
  },
  {
    id = "overscroll_stretch",
    title = "Overscroll Stretch",
    file = "stretch.glsl",
    note = "Vertical stretch; use Up/Down to control amount",
    usesInputTexture = true,
  },
  {
    id = "mario",
    title = "Mario",
    file = "mario.glsl",
    note = "Procedural Mario scene",
  },
}

return ShaderCatalog
