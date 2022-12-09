---This program manages the main storage, and dictates all access to it

--[[
Transfer queue handler function
To perform an action on the inventory queue an event (pushItems and pullItems are queued)
  "inventory", uniqueIdentifier|nil, "pushItems"|"pullItems", ...
To get your result, wait for the event
  "inventoryFinished"..uniqueIdentifier, ...
]]--

local transferQueueStart = function(config)
  local storage = require("abstractInvLib")(config.inventories)
  storage.refreshStorage()
  local transferQueue = require("common").loadTableFromFile(".cache/transferQueue") or {}

  local function transferQueueInput()
    while true do
      local e = {os.pullEvent("inventory")}
      table.insert(transferQueue, e)
      require("common").saveTableToFile(".cache/transferQueue", transferQueue)
      os.queueEvent("_performTransfer")
    end
  end

  local function transferQueueOutput()
    if #transferQueue > 0 then
      os.queueEvent("_performTransfer")
    end
    while true do
      os.pullEvent("_performTransfer")
      while #transferQueue > 0 do
        local transfer = table.remove(transferQueue, 1)
        require("common").saveTableToFile(".cache/transferQueue", transferQueue)
        local retVal = {pcall(function() return storage[transfer[3]](table.unpack(transfer,4)) end)}
        os.queueEvent("inventoryFinished"..tostring(transfer[2]), table.unpack(retVal, 2))
      end
    end
  end

  running = true
  parallel.waitForAny(transferQueueInput, transferQueueOutput)
  error("NOT RUNNING")
  running = false
end

--- Helper functions

---@param async boolean
---@param targetInventory string|AbstractInventory
---@param name string|number
---@param amount nil|number
---@param toSlot nil|number
---@param nbt nil|string
---@param options nil|TransferOptions
---@return nil|integer count
local function pushItems(async, targetInventory, name, amount, toSlot, nbt, options)
  local id = tostring({})
  os.queueEvent("inventory", id, "pushItems", targetInventory, name, amount, toSlot, nbt, options)
  if not async then
    return table.unpack({os.pullEvent("inventoryFinished"..id)}, 2)
  end
end
---@param async boolean
---@param fromInventory string|AbstractInventory
---@param fromSlot string|number
---@param amount nil|number
---@param toSlot nil|number
---@param nbt nil|string
---@param options nil|TransferOptions
---@return nil|integer count
local function pullItems(async, fromInventory, fromSlot, amount, toSlot, nbt, options)
  local id = tostring({})
  os.queueEvent("inventory", id, "pullItems", fromInventory, fromSlot, amount, toSlot, nbt, options)
  if not async then
    return table.unpack({os.pullEvent("inventoryFinished"..id)}, 2)
  end
end

local function list()
  local id = tostring({})
  os.queueEvent("inventory", id, "list")
  return table.unpack({os.pullEvent("inventoryFinished"..id)}, 2)
end


return setmetatable({
  id = "storage",
  version = "0.0",
  start = transferQueueStart,
  pushItems = pushItems,
  pullItems = pullItems,
  list = list,
}, {__index = function(t, k)
  return function(async, ...)
    local id = tostring({})
    os.queueEvent("inventory", id, k, ...)
    if not async then
      return table.unpack({os.pullEvent("inventoryFinished"..id)}, 2)
    end
  end
end})