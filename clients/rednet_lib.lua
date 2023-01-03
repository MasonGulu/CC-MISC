local lib = {}

peripheral.find("modem",rednet.open)
local host
local PROTOCOL = "STORAGE"
---Connect to the storage system
function lib.connect()
  host = assert(rednet.lookup(PROTOCOL), "Storage system is not on rednet.")
end
---Call a method remotely on the storage module
---@param method string
---@param ... any
local function storage(method, ...)
  local message = {method=method, args=table.pack(...)}
  rednet.send(host, message, PROTOCOL)
  while true do
    local from, resp, protocol = rednet.receive(PROTOCOL)
    if from == host and type(resp) == "table" and resp.method==method then
      return resp.value
    end
  end
end
---Pull items from an inventory
---@param fromInventory string|AbstractInventory
---@param fromSlot string|number
---@param amount nil|number
---@param toSlot nil|number
---@param nbt nil|string
---@param options nil|TransferOptions
function lib.pullItems(fromInventory, fromSlot, amount, toSlot, nbt, options)
  return storage("pullItems",fromInventory, fromSlot, amount, toSlot, nbt, options)
end

---Push items to an inventory
---@param targetInventory string
---@param name string|number
---@param amount nil|number
---@param toSlot nil|number
---@param nbt nil|string
---@param options nil|TransferOptions
function lib.pushItems(targetInventory, name, amount, toSlot, nbt, options)
  return storage("pushItems",targetInventory, name, amount, toSlot, nbt, options)
end

---List inventory contents
function lib.list()
  return storage("list")
end

---Subscribe to transfers
function lib.subscribe()
  rednet.send(host, "subscribe", PROTOCOL)
  while true do
    local id, message = rednet.receive(PROTOCOL)
    if type(message) == "table" and message.method == "update" then
      error("rednet?")
      os.queueEvent("update", message.value)
    end
  end
end

return lib