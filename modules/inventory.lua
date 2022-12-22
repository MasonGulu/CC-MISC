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
  },
  cacheTimer = {
    type = "number",
    description = "Sync the transfer cache to disk every n seconds.",
    default = 10,
  }
},
init = function(loaded, config)
  local storage = require("abstractInvLib")(config.inventory.inventories.value)
  storage.refreshStorage(true)
  local transferQueue = require("common").loadTableFromFile(".cache/transferQueue") or {}
  local transferTimer
  local cacheTimer = os.startTimer(config.inventory.cacheTimer.value)
  local transferQueueDiffers = false

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
          local retVal = {pcall(function() return storage[transfer[2]](table.unpack(transfer,3,transfer.n)) end)}
          if not retVal[1] then
            error(retVal[2])
          end
          os.queueEvent("inventoryFinished", transfer[1], table.unpack(retVal, 2))
        end)
      end
      transferQueueDiffers = true
      parallel.waitForAll(table.unpack(transferExecution))
    end
  end

  local function timerHandler()
    while true do
      local e, id = os.pullEvent("timer")
      if id == transferTimer then
        performTransfer()
      elseif id == cacheTimer then
        if transferQueueDiffers then
          transferQueueDiffers = false
          require("common").saveTableToFile(".cache/transferQueue", transferQueue)
        end
        cacheTimer = os.startTimer(config.inventory.cacheTimer.value)
      end
    end
  end

  local function addToQueue(...)
    table.insert(transferQueue, table.pack(...))
    if (#transferQueue > config.inventory.flushLimit.value) then
      performTransfer()
    elseif not transferTimer then
      transferTimer = os.startTimer(config.inventory.flushTimer.value)
    end
    transferQueueDiffers = true
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

  local module = {}
  for k,v in pairs(storage) do
    if k:sub(1,1) ~= "_" then
      module[k] = v
    end
  end
  module.pushItems = pushItems
  module.pullItems = pullItems
  module.start = function() parallel.waitForAny(queueHandler, timerHandler) end
  module.gui = function(frame)
    frame:addLabel():setPosition(2,2):setText("Transfer Queue Length:")
    local queueSizeLabel = frame:addLabel():setPosition(2,3):setFontSize(3)
    frame:addButton():setPosition(2,11):setSize("parent.w-2",3):setText("Flush Queue"):onClick(performTransfer)
    frame:addButton():setPosition(2,15):setSize("parent.w-2",3):setText("Clear Queue"):onClick(function()
      transferQueue = {}
    end)
    frame:addThread():start(function()
      while true do
        os.pullEvent()
        queueSizeLabel:setText(#transferQueue)
      end
    end)
  end

  return module
end,
}