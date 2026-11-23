-- gen_icon.lua : game icon -- abstract platformer mark. A dark plate, two rising
-- ledges and a dotted jump arc between them. No character, no scene.
local tasks = {}

local PAL = {
  { "ink",   "080a0b" },   -- plate edge
  { "plate", "131a1e" },   -- plate
  { "plate2","1c262c" },   -- plate light (top-left)
  { "ledge", "9aa3ae" },   -- ledge top
  { "ledge2","5a6470" },   -- ledge side
  { "ledge3","39424c" },   -- ledge underside
  { "arc",   "a8e070" },   -- jump trail
  { "arc2",  "d7ffb0" },   -- trail highlight
}

local function build(cv, C)
  -- plate: flat, rounded by clipping the corners, one line of edge light
  cv:rect(0, 0, 32, 32, "plate")
  for _, q in ipairs({ { 0, 0 }, { 31, 0 }, { 0, 31 }, { 31, 31 }, { 1, 0 }, { 0, 1 }, { 30, 0 }, { 31, 1 },
                       { 0, 30 }, { 1, 31 }, { 31, 30 }, { 30, 31 } }) do
    cv:set(q[1], q[2], "-")
  end
  cv:outline("ink")
  for x = 2, 29 do cv:set(x, 1, "plate2") end

  -- two ledges, the right one higher: the level climbs
  local ledges = { { 3, 23, 11, 4 }, { 18, 15, 11, 4 } }
  for _, l in ipairs(ledges) do
    cv:rect(l[1], l[2], l[3], l[4], "ledge2")
    cv:rect(l[1], l[2], l[3], 1, "ledge")
    cv:rect(l[1], l[2] + l[4] - 1, l[3], 1, "ledge3")
  end

  -- dotted jump arc from the left ledge over to the right one
  local x0, y0 = 12.5, 22.0
  local x1, y1 = 18.5, 14.0
  local cx, cy = 15.5, -3.0
  local steps = 120
  for i = 0, steps do
    if i % 4 == 0 then
      local t = i / steps
      local x = (1 - t) ^ 2 * x0 + 2 * (1 - t) * t * cx + t * t * x1
      local y = (1 - t) ^ 2 * y0 + 2 * (1 - t) * t * cy + t * t * y1
      local dot = (t > 0.42 and t < 0.58) and 2 or 1
      cv:rect(math.floor(x), math.floor(y), dot, dot, "arc")
      if math.abs(t - 0.5) < 0.05 then
        cv:set(math.floor(x), math.floor(y), "arc2")
      end
    end
  end
end

tasks[1] = {
  id = "icon", w = 32, h = 32, set = "game-icon", palette = PAL,
  build = function(cv, C)
    cv:sampling(1)
    build(cv, C)
  end,
}
return tasks
