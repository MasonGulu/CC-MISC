local monitorSide
if not settings.get("misc.monitor") then
  settings.define("misc.monitor", { description = "Monitor side to display on.", type = "string" })
  print("What side is the monitor on?")
  monitorSide = read()
  settings.set("misc.monitor", monitorSide)
  settings.save()
end
local textScale = 0.5

settings.load()
monitorSide = settings.get("misc.monitor")
local monitor = assert(peripheral.wrap(monitorSide), "Invalid monitor")

local lib = require("modemLib")
local modem = peripheral.getName(peripheral.find("modem"))
lib.connect(modem)

local labelFG = colors.black
local labelBG = colors.white
local usedBG = colors.red
local freeBG = colors.gray
monitor.setTextScale(textScale)
local w, h = monitor.getSize()
local barH = h - 2

local function fillRect(x, y, width, height)
  local str = string.rep(" ", width)
  for i = 0, height - 1 do
    monitor.setCursorPos(x, y + i)
    monitor.write(str)
  end
end

local setBG = monitor.setBackgroundColor
local setFG = monitor.setTextColor

local function writeUsage()
  local usage = lib.getUsage()
  setBG(labelBG)
  setFG(labelFG)
  monitor.clear()
  local slots = string.format("Total %u", usage.total)
  monitor.setCursorPos(math.floor((w - #slots) / 2), 1)
  monitor.write(slots)

  local used = string.format("Used %u", usage.used)
  monitor.setCursorPos(1, h)
  monitor.write(used)

  local free = string.format("Free %u", usage.free)
  monitor.setCursorPos(w - #free + 1, h)
  monitor.write(free)

  local usedWidth = math.floor((usage.used / usage.total) * w)
  setBG(usedBG)
  fillRect(1, 2, usedWidth, barH)
  setBG(freeBG)
  fillRect(usedWidth + 1, 2, w - usedWidth + 1, barH)
  print(1, usedWidth + 1, w - usedWidth + 1, barH)
end

local function handleUpdates()
  while true do
    local _, list = os.pullEvent("update")
    writeUsage()
  end
end

writeUsage()

parallel.waitForAny(lib.subscribe, handleUpdates)
