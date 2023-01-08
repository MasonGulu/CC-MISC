local lib = {}

local modem
local name

local hostPort = 50
local updatePort = 51
local respPort = 50
local timeout = 3000

local function validateMessage(message)
  local valid = type(message) == "table" and message.protocol ~= nil
  valid = valid and (message.destination == name or message.destination == "*")
  valid = valid and message.source ~= nil
  return valid
end
local function getModemMessage(filter, timeout)
  local timer
  if timeout then
    timer = os.startTimer(timeout)
  end
  while true do
    ---@type string, string, integer, integer, any, integer
    local event, side, channel, reply, message, distance = os.pullEvent()
    if event == "modem_message" and (filter == nil or filter(message)) then
      if timeout then
        os.cancelTimer(timer)
      end
      return {
        side = side,
        channel = channel,
        reply = reply,
        message = message,
        distance = distance
      }
    elseif event == "timer" and timeout and side == timer then
      return
    end
  end
end
---Connect to the storage system
function lib.connect(modem_name)
  modem = assert(peripheral.wrap(modem_name), "Invalid modem.")
  modem.open(respPort)
  name = modem.getNameLocal()
end
---Call an interface method remotely
---@param method string
---@param ... any
local function interface(method, ...)
  local message = {
    method = method,
    args = table.pack(...),
    protocol = "storage_system_modem",
    source = name,
    destination = "HOST"
  }
  modem.transmit(hostPort, respPort, message)
  local waitStart = os.epoch("utc")
  while true do
    local event = getModemMessage(validateMessage, 2)
    if event then
      message = event.message
      if message.protocol == "storage_system_modem" and message.method == method then
        return table.unpack(message.response)
      end
    end
    if waitStart + timeout < os.epoch("utc") then
      error("Response timed out.", 2)
    end
  end
end
---Pull items from an inventory
---@param async boolean
---@param fromInventory string|AbstractInventory
---@param fromSlot string|number
---@param amount nil|number
---@param toSlot nil|number
---@param nbt nil|string
---@param options nil|TransferOptions
function lib.pullItems(async,fromInventory, fromSlot, amount, toSlot, nbt, options)
  return interface("pullItems",async,fromInventory, fromSlot, amount, toSlot, nbt, options)
end

---Push items to an inventory
---@param async boolean
---@param targetInventory string
---@param name string|number
---@param amount nil|number
---@param toSlot nil|number
---@param nbt nil|string
---@param options nil|TransferOptions
function lib.pushItems(async,targetInventory, name, amount, toSlot, nbt, options)
  return interface("pushItems",async,targetInventory, name, amount, toSlot, nbt, options)
end

---List inventory contents
function lib.list()
  return interface("list")
end

function lib.requestCraft(name,count)
  return interface("requestCraft",name,count)
end

---Subscribe to transfers
function lib.subscribe()
  modem.open(updatePort)
  while true do
    local event = getModemMessage(validateMessage)
    assert(event, "Got no event")
    if event.message.protocol == "storage_system_update" then
      os.queueEvent("update", event.message.list)
    end
  end
end

function lib.performTransfer()
  return interface("performTransfer")
end

function lib.listCraftables()
  return interface("listCraftables")
end

function lib.startCraft(jobID)
  return interface("startCraft",jobID)
end

function lib.cancelCraft(jobID)
  return interface("cancelCraft",jobID)
end

function lib.addGridRecipe(name,produces,recipe,shaped)
  return interface("addGridRecipe", name, produces, recipe, shaped)
end

function lib.getUsage()
  return interface("getUsage")
end

return lib