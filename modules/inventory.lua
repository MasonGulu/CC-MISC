local common = require("common")
return {
id = "inventory",
version = "1.0.0",
config = {
  inventories = {
    type = "table",
    description = "List of storage peripherals to use for the main storage"
  },
  flushTimer = {
    type = "number",
    description = "Time to wait after a transfer is queued before performing the transfers",
    default = 1,
  },
  flushLimit = {
    type = "number",
    description = "Immediately flush the transfer queue when this many transfers are in it",
    default = 5,
  },
  cacheTimer = {
    type = "number",
    description = "Sync the transfer cache to disk every n seconds.",
    default = 5,
  },
  defragOnStart = {
    type = "boolean",
    description = "Defragment the storage on storage system start",
    default = true
  },
  defragEachTransfer = {
    type = "boolean",
    description = "Defragment the storage each time the queue is flushed.",
    default = false
  }
},
setup = function(moduleConfig)
  local attachedInventories = {}
  local function getAttachedInventoriesToModem(modem)
    modem = peripheral.wrap(modem)
    if not modem.isWireless() then return end
    for _, v in ipairs(modem.getNamesRemote()) do
      if peripheral.hasType(v, "inventory") then attachedInventories[#attachedInventories+1] = v end
    end
  end
  for _, v in ipairs(peripheral.getNames()) do
    if peripheral.hasType(v, "inventory") then attachedInventories[#attachedInventories+1] = v
    elseif peripheral.hasType(v, "modem") then getAttachedInventoriesToModem(v) end
  end
  print("Your storage inventory list is not setup. How would you like to set that up?")
  print("1) All inventories on the network")
  print("2) Select Y/n on each inventory on the network")
  print("3) Enter the list manually")
  while true do
    local _, char = os.pullEvent("char")
    if char == "1" then
      moduleConfig.inventories.value = attachedInventories
      return
    elseif char == "2" then
      moduleConfig.inventories.value = {}
      for k,v in pairs(attachedInventories) do
        term.write(("%s(Y/n):"):format(v))
        local input = io.read()
        if input == "" then
          input = "y"
        end
        if input:sub(1,1):lower() == "y" then
          table.insert(moduleConfig.inventories.value, v)
        end
      end
      return
    elseif char == "3" then
      while true do
        print("Enter a table:")
        local input = io.read()
        local inputT = textutils.unserialise(input)
        if inputT then
          moduleConfig.inventories.value = inputT
          return
        end
        print("Invalid table.")
      end
    end
  end
end,
init = function(loaded, config)
  local log = loaded.logger
  local storage = require("abstractInvLib")(config.inventory.inventories.value)
  storage.refreshStorage(true)
  local transferQueue = require("common").loadTableFromFile(".cache/transferQueue") or {}
  local transferTimer
  local cacheTimer = os.startTimer(config.inventory.cacheTimer.value)
  local transferQueueDiffers = false
  local inventoryLock = false

  ---Signal the system to perform a transfer
  local function performTransfer()
    if transferTimer then
      os.cancelTimer(transferTimer)
      transferTimer = nil
    end
    os.queueEvent("_performTransfer")
  end

  local function defrag()
    inventoryLock = true
    storage.defrag()
    inventoryLock = false
  end

  ---Queue handling function
  ---Waits to do an optimal transfer of the whole queue
  local function queueHandler()
    local logger = setmetatable({}, {__index=function () return function () end end})
    if log then
      logger = loaded.logger.interface.logger("inventory","queueHandler")
    end
    if #transferQueue > 0 then
      performTransfer()
    end
    while true do
      os.pullEvent("_performTransfer")
      if transferTimer then
        os.cancelTimer(transferTimer)
        transferTimer = nil
      end
      while inventoryLock do
        os.sleep(0)
      end
      if logger then
        logger:debug("Starting transfer")
      end
      local transferQueueCopy = {table.unpack(transferQueue)}
      transferQueue = {}
      local transferExecution = {}
      for _,v in pairs(transferQueueCopy) do
        local transfer = v
        table.insert(transferExecution, function ()
          logger:debug("Transfer %s %s %s %s %s %s %s %s", table.unpack(transfer))
          local retVal = table.pack(pcall(function() return storage[transfer[2]](table.unpack(transfer,3,transfer.n)) end))
          if not retVal[1] then
            logger:error("Transfer %s %s failed with %s", transfer[1], transfer[2], retVal[2])
            error(retVal[2])
          end
          logger:debug("Transfer %s %s finished, returned %s", transfer[1], transfer[2], retVal[2])
          os.queueEvent("inventoryFinished", transfer[1], table.unpack(retVal, 2))
        end)
      end
      transferQueueDiffers = true
      parallel.waitForAll(table.unpack(transferExecution))
      if config.inventory.defragEachTransfer.value then
        defrag()
      end
      os.queueEvent("inventoryUpdate", storage.list())
      if #transferQueue > 0 then
        performTransfer()
      end
    end
  end

  ---Handles timers
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

  ---Add the given arguments to the queue
  ---@param id string
  ---@param ... any
  local function addToQueue(id, ...)
    table.insert(transferQueue, table.pack(id, ...))
    if (#transferQueue > config.inventory.flushLimit.value) then
      performTransfer()
    elseif not transferTimer then
      transferTimer = os.startTimer(config.inventory.flushTimer.value)
    end
    transferQueueDiffers = true
  end

  ---Generate a pseudo random ID
  ---@return string
  local function getID()
    return tostring({})
  end

  ---Add the given arguments to the queue, generating an id
  ---@param ... any
  ---@return string
  local function queueAction(...)
    local id = getID()
    addToQueue(id, ...)
    return id
  end

  local function waitForTransfer(id)
    local e
    repeat
      e = {os.pullEvent("inventoryFinished")}
    until e[2] == id
    return e
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
    local id = queueAction("pushItems", targetInventory, name, amount, toSlot, nbt, options)
    if async then
      return id
    end
    return table.unpack(waitForTransfer(id),3)
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
    local id = queueAction("pullItems", fromInventory, fromSlot, amount, toSlot, nbt, options)
    if async then
      return id
    end
    return table.unpack(waitForTransfer(id),3)
  end

  if config.inventory.defragOnStart.value then
    print("Defragmenting...")
    local t0 = os.epoch("utc")
    storage.defrag()
    common.printf("Defrag done in %.2f seconds.",
      (os.epoch("utc")-t0)/1000)
  end

  local module = {}
  for k,v in pairs(storage) do
    if k:sub(1,1) ~= "_" then
      module[k] = v
    end
  end
  module.pushItems = pushItems
  module.pullItems = pullItems
  module.defrag = defrag
  module.start = function()
    parallel.waitForAny(queueHandler, timerHandler)
  end
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
  module.performTransfer = performTransfer

  return module
end,
}