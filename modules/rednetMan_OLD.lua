
--[[
storage,
- pullItems, async, fromInventory, fromSlot, amount, toSlot, nbt, options
- pushItems, async, targetInventory, name, amount, toSlot, nbt, options
- all other methods available from abstractInvLib
]]
local storage = require("modules.storageMan")
local function rednetStart(config)
  rednet.open(config.modem)
  rednet.host("STORAGE", config.hostname)
  local responseLookup = {
    storage = function(msg)
      if msg[2] == "pushItems" then
        return storage.pushItems(table.unpack(msg, 3))
      elseif msg[2] == "pullItems" then
        return storage.pullItems(table.unpack(msg, 3))
      end
      return storage[msg[2]](table.unpack(msg, 3))
    end
  }
  while true do
    local id, msg, protocol = rednet.receive("STORAGE")
    if type(msg) == "table" and msg[1] and responseLookup[msg[1]] then
      rednet.send(id, responseLookup[msg[1]](msg))
    end
  end
end

return {
  id = "rendet",
  version = "0.0",
  start = rednetStart,
}