local lib = {}

local host
local protocol = "STORAGE"
---Connect to the storage system
function lib.connect()
  host = assert(rednet.lookup(protocol), "Storage system is not on rednet.")
end
local function send_and_get_response(message)
  rednet.send(host, message, protocol)
  local from, message
  while from ~= host do
    from, message = rednet.receive(protocol)
  end
  return table.unpack(message)
end
---Call a method remotely on the storage module
---@param method string
---@param ... any
function lib.storage(method, ...)
  local message = {"inventory", method, ...}
  print(textutils.serialise(message))
  rednet.send(host, message, protocol)
end
---Pull items from an inventory
---@param fromInventory string|AbstractInventory
---@param fromSlot string|number
---@param amount nil|number
---@param toSlot nil|number
---@param nbt nil|string
---@param options nil|TransferOptions
function lib.pullItems(fromInventory, fromSlot, amount, toSlot, nbt, options)
  return lib.storage("pullItems", true, fromInventory, fromSlot, amount, toSlot, nbt, options)
end

return lib