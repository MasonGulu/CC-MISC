return {
id = "inventory",
version = "INDEV",
config = {
  inventories = {
    type = "table",
    description = "List of storage peripherals to use for the main storage"
  },
  flushTimer = {
    type = "number",
    description = "Time to wait after a transfer is queued before performing the transfers",
    default = 3,
  },
  flushLimit = {
    type = "number",
    description = "Immediately flush the transfer queue when this many transfers are in it",
    default = 10,
  }
},
init = function(loaded, config)
  local storage = require("abstractInvLib")(config.inventory.inventories.value)
  storage.refreshStorage()
  local transferQueue = require("common").loadTableFromFile(".cache/transferQueue") or {}
  local transferTimer

  local function eventName(id)
    return "inventoryFinished"..tostring(id)
  end

  local function performTransfer()
    if transferTimer then
      os.cancelTimer(transferTimer)
      transferTimer = nil
    end
    os.queueEvent("_performTransfer")
  end

  local function queueHandler()
    if #transferQueue > 0 then
      performTransfer()
    end
    while true do
      os.pullEvent("_performTransfer")
      local transferQueueCopy = {table.unpack(transferQueue)}
      transferQueue = {}
      local transferExecution = {}
      for _,v in pairs(transferQueueCopy) do
        local transfer = v
        table.insert(transferExecution, function ()
          local retVal = {pcall(function() return storage[transfer[2]](table.unpack(transfer,3)) end)}
          os.queueEvent(eventName(transfer[1]), table.unpack(retVal, 2))
        end)
      end
      require("common").saveTableToFile(".cache/transferQueue", transferQueue)
      parallel.waitForAll(table.unpack(transferExecution))
    end
  end

  local function timerHandler()
    while true do
      local e, id = os.pullEvent("timer")
      if id == transferTimer then
        print("Transfer timer!")
        performTransfer()
      end
    end
  end

  local function addToQueue(...)
    table.insert(transferQueue, {...})
    require("common").saveTableToFile(".cache/transferQueue", transferQueue)
    if (#transferQueue > config.inventory.flushLimit) then
      performTransfer()
    elseif not transferTimer then
      transferTimer = os.startTimer(config.inventory.flushTimer)
    end
  end

  local function getID()
    return tostring({})
  end

  local function queueAction(...)
    local id = getID()
    addToQueue(id, ...)
    return id
  end

  ---Push items to an inventory
  ---@param async boolean|nil
  ---@param targetInventory string|AbstractInventory
  ---@param name string|number
  ---@param amount nil|number
  ---@param toSlot nil|number
  ---@param nbt nil|string
  ---@param options nil|TransferOptions
  ---@return integer|string count event name in case of async
  local function pushItems(async, targetInventory, name, amount, toSlot, nbt, options)
    if async then
      return queueAction("pushItems", targetInventory, name, amount, toSlot, nbt, options)
    end
    return storage.pushItems(targetInventory, name, amount, toSlot, nbt, options)
  end

  ---Pull items from an inventory
  ---@param async boolean|nil
  ---@param fromInventory string|AbstractInventory
  ---@param fromSlot string|number
  ---@param amount nil|number
  ---@param toSlot nil|number
  ---@param nbt nil|string
  ---@param options nil|TransferOptions
  ---@return integer|string count event name in case of async
  local function pullItems(async, fromInventory, fromSlot, amount, toSlot, nbt, options)
    if async then
      return queueAction("pullItems", fromInventory, fromSlot, amount, toSlot, nbt, options)
    end
    return storage.pullItems(fromInventory, fromSlot, amount, toSlot, nbt, options)
  end

  return {
    start = function() parallel.waitForAny(queueHandler, timerHandler) end,
    test = function(...)
      local id = math.random()
      addToQueue(id, ...)
      return table.unpack({os.pullEvent(eventName(id))}, 2)
    end,
    pushItems = pushItems,
    pullItems = pullItems,
    getCount = storage.getCount,
    listNames = storage.listNames,
    listNBT = storage.listNBT,
    list = storage.list,
    size = storage.size,
    freeSpace = storage.freeSpace,
    listItems = storage.listItems,
  }
end,
}