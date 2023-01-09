-- Very basic proof of concept usage monitor
local monitorSide = "top"

local monitor = assert(peripheral.wrap(monitorSide), "Invalid monitor")

local lib = require("modemLib")
local modem = peripheral.getName(peripheral.find("modem"))
lib.connect(modem)

local function writeUsage()
  local usage = lib.getUsage()
  monitor.clear()
  monitor.setCursorPos(1,1)
  monitor.write("Total: ")
  monitor.write(string.format("%u", usage.total))
  monitor.setCursorPos(1,2)
  monitor.write("Free: ")
  monitor.write(string.format("%u", usage.free))
  monitor.setCursorPos(1,3)
  monitor.write("Used: ")
  monitor.write(string.format("%u", usage.used))
end

local function handleUpdates()
  while true do
    local _, list = os.pullEvent("update")
    writeUsage()
  end
end

writeUsage()

parallel.waitForAny(lib.subscribe, handleUpdates)