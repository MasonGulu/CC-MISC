local function saveTableToFile(file, table, compact)
  if type(compact) == "nil" then compact = true end
  local f = fs.open(file, "w")
  if not f then
    return false
  end
  f.write(textutils.serialise(table, {compact=compact}))
  f.close()
  return true
end

local function loadTableFromFile(file)
  local f = fs.open(file, "r")
  if not f then
    print("no file :(", file)
    return nil
  end
  local t = textutils.unserialise(f.readAll())
  f.close()
  return t
end

local function printf(s, ...)
  print(s:format(...))
end

local function f(s)
  local env = setmetatable({}, {__index = _ENV})
  local f = (debug.getinfo(2, "f") or {}).func
  if f then
    for i = 1, math.huge do
      local k, v = debug.getupvalue(f, i)
      if not k then break end
      env[k] = v
    end
  end
  for i = 1, math.huge do
    local k, v = debug.getlocal(2, i)
    if not k then break end
    env[k] = v
  end
  return s:gsub("%$%b{}", function(c) return table.concat({assert(load("return " .. c:sub(3, -2), "=codestr", "t", env))()}, " ") end)
end

-- Probably an abomination. I don't remember much about what it does.
local function layout(t, startX, startY, fullWidth, fullHeight, itemHeight)
  local w,h = 1,1
  itemHeight = itemHeight or 3
  itemHeight = "("..itemHeight..")"
  local lineHeight = "("..itemHeight.."+1)"
  startX, startY = startX or 2, startY or 2
  startX, startY = "("..startX..")", "("..startY..")"
  fullWidth, fullHeight = fullWidth or "(parent.w-2)", fullHeight or "(parent.h-2)"
  fullWidth, fullHeight = "("..fullWidth..")", "("..fullHeight..")"
  -- initial pass to get the width and height of the 2D array
  for k,v in pairs(t) do
    h = math.max(k,h)
    for k2,v2 in pairs(v) do
      w = math.max(k2,w)
    end
  end
  -- second pass to do width/height processing on each element
  local layoutInfo = {}
  for y = 1, h do
    layoutInfo[y] = {}
    for x = 1, w do
      local item = t[y][x]
      layoutInfo[y][x] = {
        w=1,
        h=1,
        x=x,
        y=y,
        processed = false
      } -- cell width/height
      if item == "up" then
        assert(y~=1, "Attempt to expand element above first row")
        layoutInfo[y][x] = layoutInfo[y-1][x]
        -- TODO change this so that the height is set to the distance between the two
        layoutInfo[y][x].h = y - layoutInfo[y][x].y + 1
      elseif item == "left" then
        assert(x~=1, "Attempt to expand element to left of first column")
        layoutInfo[y][x] = layoutInfo[y][x-1]
        layoutInfo[y][x].w = x - layoutInfo[y][x].x + 1
      elseif type(item) == "table" then
        -- this is an element
      elseif type(item) == "nil" then
        layoutInfo[y][x].processed = true
      else
        error("Invalid entry at "..x..","..y)
      end
    end
  end

  local calw, calh = "("..fullWidth.."/"..w..")", itemHeight
  for y = 1, h do
    for x = 1, w do
      if not layoutInfo[y][x].processed then
        local item = layoutInfo[y][x]
        item.processed = true
        -- set position and size of element, based on the calculated values
        local dw, dh = calw.."*"..item.w.."-1-.2", calh.."+".. item.h-1 .."*"..lineHeight
        t[y][x]:setSize(dw, dh)
        local dx, dy = calw.."*"..(x-1).."+0.2+"..startX, lineHeight.."*"..(y-1).."+"..startY
        t[y][x]:setPosition(dx,dy)
        print(dw, dh)
        print(dx, dy)
      end
    end
  end
end

return {
  saveTableToFile = saveTableToFile,
  loadTableFromFile = loadTableFromFile,
  printf = printf,
  f = f,
  layout = layout,
}