-- gen_backdrop.lua : builds assets/images/backdrop_well.aseprite/.png
-- 320x180 -- exactly one game frame (the viewport is 320x180 at 4x).
--
-- This is the layer BEHIND the tilemap background. It is blurred and
-- sine-warped at runtime, so it is painted as a continuous value field:
-- one hazy cave void, a soft shaft, distant pillars, near-rock silhouettes.
-- Nothing here is meant to be read at 1x, only felt.
local PROJ = app.params["proj"] or "D:\\Godot4\\GodotProject\\wellwell"
local LIB = app.params["lib"] or "D:\\Godot4\\.agents\\skills\\godot-pixel-art\\scripts\\artlib.lua"
local SRC = PROJ .. "\\art-src\\"
local OUT = PROJ .. "\\assets\\images\\backdrop_well"
local lib = dofile(LIB)

local W, H = 320, 180

--------------------------------------------------------------------------
-- palette: 11 steps of one cool well-water ramp. Max value stays under
-- 0.65 so the backdrop never competes with the terrain.
--------------------------------------------------------------------------
local PALETTE = {
  { "0", "04070b", "void" },
  { "1", "070d12", "ink" },
  { "2", "0a141b", "shadow" },
  { "3", "0d1b23", "far rock" },
  { "4", "11232c", "haze low" },
  { "5", "152e38", "haze high" },
  { "6", "1b3b44", "mist" },
  { "7", "244e54", "water" },
  { "8", "2f6465", "glint" },
  { "9", "47867f", "mote" },
  { "a", "6ba79b", "mote bright" },
}
local pal, order = lib.buildPalette(PALETTE)
local LEVEL = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a" }

local spr = Sprite(W, H, ColorMode.RGB)
local img = spr.cels[1].image
lib.applyPalette(spr, order)

local function put(x, y, ch)
  x, y = math.floor(x + 0.5), math.floor(y + 0.5)
  if x >= 0 and y >= 0 and x < W and y < H then
    img:putPixel(x, y, pal[ch])
  end
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

--------------------------------------------------------------------------
-- deterministic noise
--------------------------------------------------------------------------
local function hash2(x, y)
  local n = (x * 374761393 + y * 668265263) % 2147483647
  if n < 0 then n = n + 2147483647 end
  n = (n * 1274126177) % 2147483647
  if n < 0 then n = n + 2147483647 end
  return n / 2147483647
end

local function value_noise(x, y, cell)
  local fx, fy = x / cell, y / cell
  local x0, y0 = math.floor(fx), math.floor(fy)
  local tx, ty = fx - x0, fy - y0
  tx = tx * tx * (3 - 2 * tx)
  ty = ty * ty * (3 - 2 * ty)
  local a = hash2(x0, y0)
  local b = hash2(x0 + 1, y0)
  local c = hash2(x0, y0 + 1)
  local d = hash2(x0 + 1, y0 + 1)
  local top = a + (b - a) * tx
  local bottom = c + (d - c) * tx
  return top + (bottom - top) * ty
end

local function fbm(x, y)
  return value_noise(x, y, 52) * 0.62
    + value_noise(x, y, 19) * 0.26
    + value_noise(x, y, 7) * 0.12
end

--------------------------------------------------------------------------
-- 1. the value field: gradient + shaft + haze, quantised with a 4x4 bayer.
--    Everything is continuous here, so the shaft has no edges.
--------------------------------------------------------------------------
local STOPS = {
  { 0.00, 0.9 }, { 0.14, 2.1 }, { 0.34, 3.0 }, { 0.52, 3.8 },
  { 0.66, 3.5 }, { 0.80, 2.7 }, { 0.92, 2.1 }, { 1.00, 2.3 },
}

local function level_at(t)
  for i = 1, #STOPS - 1 do
    local a, b = STOPS[i], STOPS[i + 1]
    if t >= a[1] and t <= b[1] then
      local k = (t - a[1]) / math.max(b[1] - a[1], 0.0001)
      return a[2] + (b[2] - a[2]) * k
    end
  end
  return STOPS[#STOPS][2]
end

local BAYER = {
  { 0, 8, 2, 10 }, { 12, 4, 14, 6 }, { 3, 11, 1, 9 }, { 15, 7, 13, 5 },
}

local SHAFT_X = 206.0

local function shaft_at(x, y)
  local t = y / H
  local cx = SHAFT_X - 20 * t
  local half = 15 + 42 * t
  local d = (x - cx) / half
  local core = math.exp(-d * d * 2.4)
  local open_up = clamp((t - 0.02) / 0.18, 0.0, 1.0)   -- dims out at very top
  local fade_down = 1.0 - 0.62 * t
  return core * open_up * fade_down * 2.05
end

local function haze_at(x, y)
  local dx = (x - 196) / 165.0
  local dy = (y - 74) / 128.0
  return math.exp(-(dx * dx + dy * dy) * 1.9) * 1.05
end

for y = 0, H - 1 do
  local base = level_at(y / (H - 1))
  for x = 0, W - 1 do
    local cloudy = (fbm(x, y) - 0.5) * 1.15
    local v = base + shaft_at(x, y) + haze_at(x, y) + cloudy
    -- pull the corners down so the composition breathes in the middle
    local vx = (x - W * 0.5) / (W * 0.5)
    local vy = (y - H * 0.44) / (H * 0.5)
    v = v - (vx * vx * 0.55 + vy * vy * 0.75) * 0.9
    local d = (BAYER[y % 4 + 1][x % 4 + 1] + 0.5) / 16.0
    put(x, y, LEVEL[clamp(math.floor(v + d), 0, 10) + 1])
  end
end

--------------------------------------------------------------------------
-- 2. (deliberately empty: no architecture here. The tilemap owns every
--    readable shape; this plate is only light, mist and depth.)
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- 3. distant shore: a soft hump line just above the water
--------------------------------------------------------------------------
for x = 0, W - 1 do
  local gy = 150 + (value_noise(x, 5, 26) - 0.5) * 9
  for y = math.floor(gy), 157 do
    put(x, y, "2")
  end
  put(x, gy - 1, "3")
  if value_noise(x, 61, 6) > 0.55 then
    put(x, gy - 2, "4")
  end
end

--------------------------------------------------------------------------
-- 4. water: a horizon, broken ripples, a couple of cold glints
--------------------------------------------------------------------------
local HORIZON = 158
for y = HORIZON, H - 1 do
  for x = 0, W - 1 do
    local ch = "1"
    if y == HORIZON then
      ch = (value_noise(x, 11, 5) > 0.34) and "6" or "4"
    elseif y == HORIZON + 1 then
      ch = (value_noise(x, 23, 4) > 0.45) and "5" or "3"
    elseif y > H - 5 then
      ch = "0"
    end
    put(x, y, ch)
  end
end
for x = 0, W - 1 do
  if value_noise(x, 3, 6) > 0.66 then put(x, HORIZON + 3, "7") end
  if value_noise(x, 33, 11) > 0.88 then put(x, HORIZON + 5, "8") end
  if value_noise(x, 77, 17) > 0.90 then put(x, HORIZON + 8, "7") end
end

--------------------------------------------------------------------------
-- 5. near rock: ceiling mass with four irregular stalactites, side walls
--------------------------------------------------------------------------
local function ceiling_y(x)
  return 5 + value_noise(x, 11, 38) * 20 + value_noise(x, 71, 11) * 8
end

local SPIKES = {
  { 56, 8, 26 }, { 121, 11, 46 }, { 205, 5, 18 }, { 277, 9, 33 },
}
for _, s in ipairs(SPIKES) do
  local top = ceiling_y(s[1])
  for i = 0, s[3] do
    local t = i / s[3]
    local half = (s[2] * 0.5) * (1.0 - t * 0.9) + 0.5
    for x = math.floor(s[1] - half + 0.5), math.floor(s[1] + half + 0.5) do
      put(x, top + i, "1")
    end
  end
end

for x = 0, W - 1 do
  local top = ceiling_y(x)
  for y = 0, math.floor(top) do
    put(x, y, "1")
  end
  put(x, top + 1, "2")
  if value_noise(x, 7, 9) > 0.66 then
    put(x, top + 2, "3")
  end
end

for y = 0, H - 1 do
  local l = 9 + value_noise(y, 3, 13) * 13 + value_noise(y, 43, 5) * 4
  local r = 9 + value_noise(y, 91, 13) * 13 + value_noise(y, 143, 5) * 4
  for x = 0, math.floor(l) do put(x, y, "1") end
  for x = W - 1, math.floor(W - 1 - r), -1 do put(x, y, "1") end
  put(l + 1, y, "2")
  put(W - 2 - r, y, "2")
end

--------------------------------------------------------------------------
-- 6. motes: dust in the shaft, three that survive the blur as glows
--------------------------------------------------------------------------
for i = 0, 26 do
  local x = math.floor(hash2(i, 101) * W)
  local y = math.floor(20 + hash2(i, 211) * (HORIZON - 28))
  local mdx = (x - 190) / 62.0
  if math.exp(-mdx * mdx) > 0.30 then
    local roll = hash2(i, 307)
    local ch = "5"
    if roll > 0.45 then ch = "6" end
    if roll > 0.80 then ch = "7" end
    put(x, y, ch)
  end
end
for _, m in ipairs({ { 178, 52 }, { 212, 98 }, { 158, 127 } }) do
  put(m[1], m[2], "a")
  put(m[1] - 1, m[2], "8")
  put(m[1] + 1, m[2], "8")
  put(m[1], m[2] - 1, "9")
  put(m[1], m[2] + 1, "9")
end

lib.save(spr, OUT)
print("colors used: " .. #lib.usedColors(img))

--------------------------------------------------------------------------
-- preview: 3x on the darkest room colour so the ramp is judged in context
--------------------------------------------------------------------------
local SCALE = 3
local p = Sprite(W * SCALE, H * SCALE, ColorMode.RGB)
local pimg = p.cels[1].image
for y = 0, p.height - 1 do
  for x = 0, p.width - 1 do
    pimg:putPixel(x, y, lib.hex("0a0f12"))
  end
end
for y = 0, H - 1 do
  for x = 0, W - 1 do
    local c = lib.unpack(img:getPixel(x, y))
    if c.a > 0 then
      for sy = 0, SCALE - 1 do
        for sx = 0, SCALE - 1 do
          pimg:putPixel(x * SCALE + sx, y * SCALE + sy, Color(c.r, c.g, c.b, 255))
        end
      end
    end
  end
end
p:saveAs(SRC .. "preview_backdrop.png")
print("preview written: preview_backdrop.png")
app.exit()
